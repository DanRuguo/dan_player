//! One bounded LRC transformer shared by embedded tags and external lyric files.
use anyhow::ensure;

pub(super) const WARNING: &str = "TRIM_LYRICS_UNSUPPORTED";
pub(super) struct TrimmedLyric {
    pub text: String,
    pub adjusted: bool,
    pub warning: Option<&'static str>,
}

pub(super) fn bounds(start: f64, end: f64) -> anyhow::Result<(i64, i64)> {
    ensure!(
        start.is_finite()
            && end.is_finite()
            && start >= 0.0
            && end > start
            && end < (i64::MAX / 4) as f64 / 1000.0,
        "TRIM_RANGE_INVALID|裁剪时间范围无效"
    );
    let result = (
        (start * 1000.0).round() as i64,
        (end * 1000.0).round() as i64,
    );
    ensure!(result.1 > result.0, "TRIM_RANGE_INVALID|裁剪片段短于1毫秒");
    Ok(result)
}

fn timestamp(text: &str) -> Option<i64> {
    let parts: Vec<_> = text.trim().split(':').collect();
    if !(2..=3).contains(&parts.len()) {
        return None;
    }
    let first = parts[0].parse::<i64>().ok()?;
    let (hours, minutes, seconds) = if parts.len() == 2 {
        (0, first, parts[1])
    } else {
        (first, parts[1].parse::<i64>().ok()?, parts[2])
    };
    let seconds = seconds.parse::<f64>().ok()?;
    if hours < 0
        || minutes < 0
        || (parts.len() == 3 && minutes >= 60)
        || !seconds.is_finite()
        || !(0.0..60.0).contains(&seconds)
    {
        return None;
    }
    hours
        .checked_mul(3600000)?
        .checked_add(minutes.checked_mul(60000)?)?
        .checked_add((seconds * 1000.0).round() as i64)
}

fn stamp(time: i64) -> String {
    format!(
        "[{:02}:{:02}.{:03}]",
        time / 60000,
        time / 1000 % 60,
        time % 1000
    )
}
fn suspicious_timing(text: &str) -> bool {
    text.contains("-->")
        || text.contains("<tt")
        || text.contains("<Lyric")
        || text.contains("[Script Info]")
        || text.split('<').skip(1).any(|part| {
            part.chars().next().is_some_and(|c| c.is_ascii_digit())
                && part
                    .split('>')
                    .next()
                    .is_some_and(|tag| tag.contains(':') || tag.contains(','))
        })
        || text.split('[').skip(1).any(|part| {
            part.chars().next().is_some_and(|c| c.is_ascii_digit())
                && part
                    .split(']')
                    .next()
                    .is_some_and(|tag| tag.contains(',') && !tag.contains(':'))
        })
}

pub(super) fn transform(text: &str, start: i64, end: i64) -> TrimmedLyric {
    let unchanged = |warning| TrimmedLyric {
        text: text.into(),
        adjusted: false,
        warning,
    };
    if text.len() > 4 * 1024 * 1024 || suspicious_timing(text) {
        return unchanged(Some(WARNING));
    }
    let mut offset = 0i64;
    let mut offset_found = false;
    for line in text.lines() {
        let line = line.trim().trim_start_matches('\u{feff}');
        if let Some(body) = line
            .strip_prefix('[')
            .and_then(|line| line.strip_suffix(']'))
        {
            if let Some((key, value)) = body.split_once(':') {
                if key.trim().eq_ignore_ascii_case("offset") && !offset_found {
                    match value.trim().parse::<i64>() {
                        Ok(value) => {
                            offset = value;
                            offset_found = true;
                        }
                        Err(_) => return unchanged(Some(WARNING)),
                    }
                }
            }
        }
    }
    let mut headers = Vec::new();
    let mut entries = Vec::new();
    let mut untimed_content = false;
    for line in text.lines() {
        let mut rest = line.trim().trim_start_matches('\u{feff}');
        if rest.is_empty() {
            continue;
        }
        let mut times = Vec::new();
        while let Some(after) = rest.strip_prefix('[') {
            let Some(close) = after.find(']') else {
                break;
            };
            let tag = &after[..close];
            if let Some(time) = timestamp(tag) {
                times.push(time);
                rest = after[close + 1..].trim_start();
            } else {
                break;
            }
        }
        if times.is_empty() {
            if let Some(body) = rest
                .strip_prefix('[')
                .and_then(|line| line.strip_suffix(']'))
            {
                if let Some((key, _)) = body.split_once(':') {
                    if key
                        .trim()
                        .chars()
                        .all(|c| c.is_ascii_alphabetic() || c == '_')
                    {
                        if key.trim().eq_ignore_ascii_case("offset") {
                            continue;
                        }
                        if key.trim().eq_ignore_ascii_case("length") {
                            headers.push(format!(
                                "[length:{:02}:{:02}]",
                                (end - start) / 60000,
                                (end - start) / 1000 % 60
                            ));
                        } else {
                            headers.push(rest.to_string());
                        }
                        continue;
                    }
                }
            }
            untimed_content = true;
        } else {
            if entries.len() + times.len() > 200000 {
                return unchanged(Some(WARNING));
            }
            let content: std::sync::Arc<str> = rest.into();
            for time in times {
                let Some(time) = time.checked_sub(offset) else {
                    return unchanged(Some(WARNING));
                };
                entries.push((time.max(0), content.clone()));
            }
        }
    }
    if entries.is_empty() {
        let unknown = text.split('[').skip(1).any(|part| {
            part.chars().next().is_some_and(|c| c.is_ascii_digit())
                && part.split(']').next().is_some_and(|tag| tag.contains(':'))
        });
        return unchanged(unknown.then_some(WARNING));
    }
    if untimed_content {
        return unchanged(Some(WARNING));
    }
    entries.sort_by_key(|entry| entry.0); // stable: translations retain their order
    let at_start = entries.iter().any(|entry| entry.0 == start);
    let previous = if at_start {
        None
    } else {
        entries
            .iter()
            .filter(|entry| entry.0 < start)
            .map(|entry| entry.0)
            .next_back()
    };
    let mut output_bytes: usize = headers.iter().map(|line| line.len() + 2).sum();
    for (time, content) in entries {
        if (time >= start && time < end) || Some(time) == previous {
            output_bytes += content.len() + 32;
            if output_bytes > 4 * 1024 * 1024 {
                return unchanged(Some(WARNING));
            }
            headers.push(format!("{}{}", stamp((time - start).max(0)), content));
        }
    }
    let newline = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let mut result = headers.join(newline);
    if text.starts_with('\u{feff}') {
        result.insert(0, '\u{feff}');
    }
    if text.ends_with('\n') && !result.is_empty() {
        result.push_str(newline);
    }
    TrimmedLyric {
        text: result,
        adjusted: true,
        warning: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn crop_keeps_previous_translation_group_at_zero_and_excludes_end() {
        let output = transform(
            "[ar:Artist]\n[00:01.00]first\n[00:01.00]译文\n[00:03.00]next\n[00:05.00]outside\n",
            2000,
            5000,
        );
        assert_eq!(
            output.text,
            "[ar:Artist]\n[00:00.000]first\n[00:00.000]译文\n[00:01.000]next\n"
        );
        assert!(output.warning.is_none());
    }
    #[test]
    fn positive_and_negative_offset_follow_player_sign_and_are_absorbed() {
        assert_eq!(
            transform("[offset:500]\n[00:02.00]A\n[00:04.00]B", 1000, 3500).text,
            "[00:00.500]A"
        );
        assert_eq!(
            transform("[offset:-500]\n[00:01.00]A\n[00:03.00]B", 1000, 3500).text,
            "[00:00.500]A"
        );
    }
    #[test]
    fn multi_timestamp_expands_and_exact_start_replaces_previous() {
        assert_eq!(
            transform("[00:01][00:03][00:05]repeat\n[00:02]earlier", 3000, 5000).text,
            "[00:00.000]repeat"
        );
    }
    #[test]
    fn blank_event_and_header_format_are_kept() {
        assert_eq!(
            transform(
                "\u{feff}[length:01:30]\r\n[00:01]line\r\n[00:02]\r\n[00:05]new\r\n",
                3000,
                6000
            )
            .text,
            "\u{feff}[length:00:03]\r\n[00:00.000]\r\n[00:02.000]new\r\n"
        );
    }
    #[test]
    fn pure_text_is_unchanged_and_unknown_timed_formats_warn() {
        for text in ["Pure lyrics\n第二行", "[Verse 1]\nwords", ""] {
            let value = transform(text, 1000, 2000);
            assert_eq!(value.text, text);
            assert!(!value.adjusted);
            assert!(value.warning.is_none());
        }
        for text in [
            "[00:01]<00:01.200>word",
            "1\n00:00:01,000 --> 00:00:02,000\nline",
            "[100,200]<0,200,0>字",
            "[00:01]line\nunknown continuation",
        ] {
            let value = transform(text, 1000, 2000);
            assert_eq!(value.text, text);
            assert_eq!(value.warning, Some(WARNING));
        }
    }
    #[test]
    fn invalid_ranges_are_rejected() {
        for range in [
            (f64::NAN, 2.0),
            (-1.0, 2.0),
            (2.0, 2.0),
            (3.0, 2.0),
            (0.0, f64::INFINITY),
        ] {
            assert!(bounds(range.0, range.1).is_err());
        }
    }

    #[test]
    fn repeated_timestamps_cannot_expand_large_text_without_a_budget() {
        let text = format!(
            "[00:01][00:02][00:03][00:04][00:05]{}",
            "x".repeat(1024 * 1024)
        );
        let value = transform(&text, 0, 6000);
        assert_eq!(value.warning, Some(WARNING));
        assert_eq!(value.text, text);
    }
}
