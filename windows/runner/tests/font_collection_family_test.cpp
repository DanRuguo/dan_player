#include "../desktop_integration_fonts.h"

#include <iostream>

namespace {
int checks = 0, scenarios = 0;

bool Check(bool value, const char* description) {
  ++checks;
  if (!value) std::cerr << "FAIL " << description << '\n';
  return value;
}

// All file/name expectations are supplied by the isolated runner. No installed
// system collection or machine-specific font name is required by this target.
struct Fixture {
  std::wstring path, requested, expected;
};

bool Probe(const Fixture& fixture, bool policy, bool realized_matches = true) {
  ++scenarios;
  desktop_integration::PopupFonts fonts;
  desktop_integration::NativeFontPolicy snapshot;
  snapshot.mixed_scripts = false;
  for (auto& face : snapshot.faces) {
    face = {fixture.requested, fixture.path};
  }
  snapshot.base_fallback = snapshot.faces[0];
  const auto configure = [&]() {
    return policy ? fonts.Configure(snapshot)
                  : fonts.Configure(fixture.requested, fixture.path);
  };
  if (!Check(configure(), "a fresh font request configures") ||
      !Check(fonts.face() == fixture.expected, "the selected native family matches")) {
    std::wcerr << L"requested=" << fixture.requested
               << L" expected=" << fixture.expected
               << L" actual=" << fonts.face() << L'\n';
    return false;
  }
  if (policy) {
    if (!Check(fonts.policy().has_value(), "font policy is retained")) return false;
  } else if (!Check(fonts.private_font_loaded(), "the provided font is private")) {
    return false;
  }
  fonts.Ensure(96);
  HDC canvas = CreateCompatibleDC(nullptr);
  if (!Check(canvas != nullptr, "memory font measuring DC exists")) return false;
  const auto old = SelectObject(canvas, fonts.row());
  wchar_t actual[LF_FACESIZE]{};
  LOGFONTW definition{};
  const bool read_face = GetTextFaceW(canvas, LF_FACESIZE, actual) > 0;
  const bool read_definition =
      GetObjectW(fonts.row(), sizeof(definition), &definition) ==
      static_cast<int>(sizeof(definition));
  SelectObject(canvas, old);
  DeleteDC(canvas);
  if (!Check(read_face && *actual, "the font handle realizes a native face") ||
      !Check(read_definition, "font handle properties are available") ||
      !Check(fixture.expected == definition.lfFaceName,
             "the HFONT uses the selected family") ||
      !Check(!realized_matches || _wcsicmp(actual, fixture.expected.c_str()) == 0,
             "GDI realizes the requested available family")) {
    std::wcerr << L"requested=" << fixture.requested
               << L" expected=" << fixture.expected
               << L" configured=" << definition.lfFaceName
               << L" realized=" << actual << L'\n';
    std::cerr << "realized UTF16:";
    for (const wchar_t character : std::wstring(actual)) {
      std::cerr << ' ' << std::hex << static_cast<unsigned>(character);
    }
    std::cerr << std::dec << '\n';
    return false;
  }
  const auto cached = fonts.row();
  if (!Check(!configure(), "equal snapshots do not reconfigure fonts")) return false;
  fonts.Ensure(96);
  if (!Check(fonts.row() == cached, "equal snapshots retain the font handle")) return false;
  std::wcout << L"PASS " << (policy ? L"policy" : L"legacy")
             << L" requested=" << fixture.requested
             << L" resolved=" << fonts.face() << L" realized="
             << (realized_matches ? actual : L"(system fallback)") << L'\n';
  return true;
}

bool UnknownAlias(const Fixture& fixture) {
  // The pre-existing fallback preserves a caller's alias for a multi-family
  // collection, while a single-family file can resolve that alias unambiguously.
  Gdiplus::PrivateFontCollection collection;
  if (!Check(collection.AddFontFile(fixture.path.c_str()) == Gdiplus::Ok,
             "fallback fixture is a readable private font")) return false;
  const int families = collection.GetFamilyCount();
  if (!Check(families > 0, "fallback fixture contains a native family")) return false;
  Fixture alias{fixture.path, L"QA Unmatched Loader Alias",
                families == 1 ? fixture.expected : L"QA Unmatched Loader Alias"};
  for (const bool policy : {false, true}) {
    if (!Probe(alias, policy, families == 1)) return false;
  }
  return true;
}
}  // namespace

// Native GDI/GDI+ only: no Flutter engine, menu, user HWND or audio endpoint.
int wmain(int argc, wchar_t** argv) {
  if (!Check(argc >= 4 && (argc - 1) % 3 == 0,
             "arguments are font path / requested full name / expected family triples")) {
    return 1;
  }
  // Keep GDI+ available between individual PopupFonts instances when examining
  // the unmatched-alias fixture's number of families.
  desktop_integration::PopupFonts font_runtime;
  Fixture final_fixture;
  for (int index = 1; index < argc; index += 3) {
    final_fixture = {argv[index], argv[index + 1], argv[index + 2]};
    if (!Check(GetFileAttributesW(final_fixture.path.c_str()) != INVALID_FILE_ATTRIBUTES,
               "every provided font fixture exists")) return 1;
    for (const bool policy : {false, true}) {
      if (!Probe(final_fixture, policy)) return 1;
    }
  }
  // Explicit exact-family requests must beat shorter sibling prefixes.
  const Fixture exact{final_fixture.path, final_fixture.expected, final_fixture.expected};
  for (const bool policy : {false, true}) {
    if (!Probe(exact, policy)) return 1;
  }
  if (!UnknownAlias(final_fixture)) return 1;
  std::cout << scenarios << " native font family scenarios / " << checks
            << " checks passed (no GUI)\n";
  return 0;
}
