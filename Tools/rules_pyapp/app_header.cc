#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

const char kMagic[8] = {'P', 'Y', 'A', 'P', 'P', 'W', 'I', 'N'};

struct Sha256 {
  uint32_t state[8];
  uint64_t count;
  uint8_t buffer[64];
};

uint32_t Rotr(uint32_t value, int bits) { return (value >> bits) | (value << (32 - bits)); }

void Sha256Block(Sha256* sha, const uint8_t* block) {
  static const uint32_t k[64] = {
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
  uint32_t w[64];
  for (int i = 0; i < 16; ++i) {
    w[i] = (uint32_t(block[i * 4]) << 24) | (uint32_t(block[i * 4 + 1]) << 16) |
           (uint32_t(block[i * 4 + 2]) << 8) | uint32_t(block[i * 4 + 3]);
  }
  for (int i = 16; i < 64; ++i) {
    uint32_t s0 = Rotr(w[i - 15], 7) ^ Rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = Rotr(w[i - 2], 17) ^ Rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t v[8];
  for (int i = 0; i < 8; ++i) v[i] = sha->state[i];
  for (int i = 0; i < 64; ++i) {
    uint32_t s1 = Rotr(v[4], 6) ^ Rotr(v[4], 11) ^ Rotr(v[4], 25);
    uint32_t ch = (v[4] & v[5]) ^ (~v[4] & v[6]);
    uint32_t t1 = v[7] + s1 + ch + k[i] + w[i];
    uint32_t s0 = Rotr(v[0], 2) ^ Rotr(v[0], 13) ^ Rotr(v[0], 22);
    uint32_t maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
    uint32_t t2 = s0 + maj;
    v[7] = v[6];
    v[6] = v[5];
    v[5] = v[4];
    v[4] = v[3] + t1;
    v[3] = v[2];
    v[2] = v[1];
    v[1] = v[0];
    v[0] = t1 + t2;
  }
  for (int i = 0; i < 8; ++i) sha->state[i] += v[i];
}

void Sha256Init(Sha256* sha) {
  static const uint32_t seed[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  for (int i = 0; i < 8; ++i) sha->state[i] = seed[i];
  sha->count = 0;
}

void Sha256Update(Sha256* sha, const uint8_t* data, size_t length) {
  size_t used = sha->count % 64;
  sha->count += length;
  if (used) {
    size_t fill = 64 - used;
    if (length < fill) {
      memcpy(sha->buffer + used, data, length);
      return;
    }
    memcpy(sha->buffer + used, data, fill);
    Sha256Block(sha, sha->buffer);
    data += fill;
    length -= fill;
  }
  while (length >= 64) {
    Sha256Block(sha, data);
    data += 64;
    length -= 64;
  }
  if (length) memcpy(sha->buffer, data, length);
}

void Sha256Final(Sha256* sha, uint8_t out[32]) {
  uint64_t bits = sha->count * 8;
  size_t used = sha->count % 64;
  uint8_t pad = 0x80;
  Sha256Update(sha, &pad, 1);
  uint8_t zero = 0;
  while ((sha->count % 64) != 56) Sha256Update(sha, &zero, 1);
  uint8_t length[8];
  for (int i = 0; i < 8; ++i) length[i] = uint8_t(bits >> (56 - i * 8));
  (void)used;
  for (int i = 0; i < 8; ++i) {
    uint8_t byte = length[i];
    memcpy(sha->buffer + (sha->count % 64), &byte, 1);
    sha->count += 1;
    if ((sha->count % 64) == 0) Sha256Block(sha, sha->buffer);
  }
  for (int i = 0; i < 8; ++i) {
    out[i * 4] = uint8_t(sha->state[i] >> 24);
    out[i * 4 + 1] = uint8_t(sha->state[i] >> 16);
    out[i * 4 + 2] = uint8_t(sha->state[i] >> 8);
    out[i * 4 + 3] = uint8_t(sha->state[i]);
  }
}

std::wstring Widen(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

std::wstring ModulePath() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) return {};
    if (length < path.size()) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

std::wstring Variable(const wchar_t* name) {
  DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
  if (size == 0) return {};
  std::wstring value(size, L'\0');
  value.resize(GetEnvironmentVariableW(name, value.data(), size));
  return value;
}

std::wstring Quote(const std::wstring& argument) {
  if (!argument.empty() && argument.find_first_of(L" \t\n\v\"") == std::wstring::npos) return argument;
  std::wstring quoted = L"\"";
  for (auto it = argument.begin();; ++it) {
    size_t backslashes = 0;
    while (it != argument.end() && *it == L'\\') {
      ++it;
      ++backslashes;
    }
    if (it == argument.end()) {
      quoted.append(backslashes * 2, L'\\');
      break;
    }
    quoted.append(*it == L'"' ? backslashes * 2 + 1 : backslashes, L'\\');
    quoted.push_back(*it);
  }
  quoted.push_back(L'"');
  return quoted;
}

std::wstring Forwarded() {
  const wchar_t* line = GetCommandLineW();
  if (*line == L'"') {
    ++line;
    while (*line && *line != L'"') ++line;
    if (*line) ++line;
  } else {
    while (*line && *line != L' ' && *line != L'\t') ++line;
  }
  while (*line == L' ' || *line == L'\t') ++line;
  return line;
}

BOOL WINAPI LeaveToTheChild(DWORD) { return TRUE; }

int Fail(const std::wstring& message) {
  fwprintf(stderr, L"%ls (error %lu)\n", message.c_str(), GetLastError());
  return 1;
}

bool ReadAt(HANDLE file, uint64_t offset, void* out, size_t size) {
  LARGE_INTEGER where;
  where.QuadPart = static_cast<LONGLONG>(offset);
  if (!SetFilePointerEx(file, where, nullptr, FILE_BEGIN)) return false;
  uint8_t* cursor = static_cast<uint8_t*>(out);
  while (size > 0) {
    DWORD chunk = size > (1u << 20) ? (1u << 20) : static_cast<DWORD>(size);
    DWORD read = 0;
    if (!ReadFile(file, cursor, chunk, &read, nullptr) || read == 0) return false;
    cursor += read;
    size -= read;
  }
  return true;
}

uint32_t Field(const uint8_t* at) {
  return uint32_t(at[0]) | (uint32_t(at[1]) << 8) | (uint32_t(at[2]) << 16) | (uint32_t(at[3]) << 24);
}

uint64_t Octal(const uint8_t* at, size_t length) {
  uint64_t value = 0;
  for (size_t i = 0; i < length; ++i) {
    if (at[i] < '0' || at[i] > '7') break;
    value = value * 8 + (at[i] - '0');
  }
  return value;
}

std::wstring Backslashed(const std::wstring& base, const std::string& relative) {
  std::wstring path = base;
  for (wchar_t c : Widen(relative)) path.push_back(c == L'/' ? L'\\' : c);
  return path;
}

void MakeParents(const std::wstring& path) {
  for (size_t at = path.find(L'\\'); at != std::wstring::npos; at = path.find(L'\\', at + 1)) {
    if (at == 0) continue;
    CreateDirectoryW(path.substr(0, at).c_str(), nullptr);
  }
}

bool WriteWhole(const std::wstring& path, const uint8_t* data, uint64_t size) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const uint8_t* cursor = data;
  while (size > 0) {
    DWORD chunk = size > (1u << 20) ? (1u << 20) : static_cast<DWORD>(size);
    DWORD wrote = 0;
    if (!WriteFile(file, cursor, chunk, &wrote, nullptr)) {
      CloseHandle(file);
      return false;
    }
    cursor += wrote;
    size -= wrote;
  }
  CloseHandle(file);
  return true;
}

bool Extract(const uint8_t* payload, uint64_t size, const std::wstring& root) {
  uint64_t at = 0;
  while (at + 512 <= size) {
    const uint8_t* header = payload + at;
    at += 512;
    bool empty = true;
    for (int i = 0; i < 512; ++i) {
      if (header[i]) {
        empty = false;
        break;
      }
    }
    if (empty) continue;
    std::string name(reinterpret_cast<const char*>(header), strnlen(reinterpret_cast<const char*>(header), 100));
    std::string prefix(reinterpret_cast<const char*>(header + 345), strnlen(reinterpret_cast<const char*>(header + 345), 155));
    std::string relative = prefix.empty() ? name : prefix + "/" + name;
    uint64_t length = Octal(header + 124, 12);
    char typeflag = static_cast<char>(header[156]);
    std::wstring path = Backslashed(root + L"\\", relative);
    if (typeflag == '5') {
      MakeParents(path + L"\\");
      CreateDirectoryW(path.c_str(), nullptr);
    } else if (typeflag == '0' || typeflag == 0) {
      if (at + length > size) return false;
      MakeParents(path);
      if (!WriteWhole(path, payload + at, length)) return false;
    }
    at += (length + 511) & ~uint64_t(511);
  }
  return true;
}

void RemoveTree(const std::wstring& path) {
  WIN32_FIND_DATAW found;
  HANDLE search = FindFirstFileW((path + L"\\*").c_str(), &found);
  if (search != INVALID_HANDLE_VALUE) {
    do {
      std::wstring name = found.cFileName;
      if (name == L"." || name == L"..") continue;
      std::wstring child = path + L"\\" + name;
      if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        RemoveTree(child);
      } else {
        SetFileAttributesW(child.c_str(), FILE_ATTRIBUTE_NORMAL);
        DeleteFileW(child.c_str());
      }
    } while (FindNextFileW(search, &found));
    FindClose(search);
  }
  RemoveDirectoryW(path.c_str());
}

std::wstring CacheRoot() {
  std::wstring root = Variable(L"GTVPN_CACHE");
  if (!root.empty()) return root;
  root = Variable(L"XDG_CACHE_HOME");
  if (!root.empty()) return root + L"\\gtvpn";
  return Variable(L"USERPROFILE") + L"\\.cache\\gtvpn";
}

std::wstring Hex(const uint8_t digest[32]) {
  static const wchar_t* digits = L"0123456789abcdef";
  std::wstring text;
  for (int i = 0; i < 32; ++i) {
    text.push_back(digits[digest[i] >> 4]);
    text.push_back(digits[digest[i] & 0xf]);
  }
  return text;
}

bool Exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

struct Trailer {
  uint64_t offset;
  uint64_t size;
  uint8_t sha[32];
  std::string name;
  std::string program;
  std::string module;
};

bool Parse(const std::vector<uint8_t>& blob, Trailer* trailer) {
  if (blob.size() < 56 || memcmp(blob.data(), kMagic, 8) != 0) return false;
  memcpy(&trailer->offset, blob.data() + 8, 8);
  memcpy(&trailer->size, blob.data() + 16, 8);
  memcpy(trailer->sha, blob.data() + 24, 32);
  size_t at = 56;
  std::string* fields[3] = {&trailer->name, &trailer->program, &trailer->module};
  for (std::string* out : fields) {
    if (at + 4 > blob.size()) return false;
    uint32_t length = Field(blob.data() + at);
    at += 4;
    if (at + length > blob.size()) return false;
    out->assign(reinterpret_cast<const char*>(blob.data() + at), length);
    at += length;
  }
  return true;
}

}

int main() {
  std::wstring self = ModulePath();
  if (self.empty()) return Fail(L"cannot find this launcher's own path");
  HANDLE file = CreateFileW(self.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return Fail(L"cannot open " + self);
  LARGE_INTEGER total;
  if (!GetFileSizeEx(file, &total)) return Fail(L"cannot size " + self);

  uint8_t footer[4];
  if (!ReadAt(file, static_cast<uint64_t>(total.QuadPart) - 4, footer, 4)) return Fail(L"cannot read the trailer size");
  uint32_t trailer_size = Field(footer);
  std::vector<uint8_t> blob(trailer_size);
  if (!ReadAt(file, static_cast<uint64_t>(total.QuadPart) - trailer_size, blob.data(), trailer_size)) {
    return Fail(L"cannot read the trailer");
  }
  Trailer trailer;
  if (!Parse(blob, &trailer)) {
    fwprintf(stderr, L"%ls is corrupt: it carries no pyapp trailer\n", self.c_str());
    return 65;
  }

  std::wstring name = Widen(trailer.name);
  std::wstring root = CacheRoot();
  std::wstring apps = root + L"\\apps\\" + name;
  std::wstring app = apps + L"\\" + Hex(trailer.sha);
  std::wstring complete = app + L"\\.complete";

  if (!Exists(complete)) {
    std::wstring guard = L"Local\\pyapp-" + name + L"-" + Hex(trailer.sha);
    HANDLE mutex = CreateMutexW(nullptr, FALSE, guard.c_str());
    if (mutex) WaitForSingleObject(mutex, INFINITE);
    if (!Exists(complete)) {
      std::vector<uint8_t> payload(trailer.size);
      if (!ReadAt(file, trailer.offset, payload.data(), trailer.size)) {
        if (mutex) ReleaseMutex(mutex);
        return Fail(L"cannot read the payload of " + self);
      }
      Sha256 sha;
      Sha256Init(&sha);
      Sha256Update(&sha, payload.data(), payload.size());
      uint8_t found[32];
      Sha256Final(&sha, found);
      if (memcmp(found, trailer.sha, 32) != 0) {
        fwprintf(stderr, L"%ls: %ls is corrupt: its payload hashes to %ls, not %ls; download it again\n",
                 name.c_str(), self.c_str(), Hex(found).c_str(), Hex(trailer.sha).c_str());
        if (mutex) ReleaseMutex(mutex);
        return 65;
      }
      RemoveTree(app);
      MakeParents(app + L"\\");
      CreateDirectoryW(app.c_str(), nullptr);
      fwprintf(stderr, L"%ls: unpacking into %ls\n", name.c_str(), app.c_str());
      if (!Extract(payload.data(), payload.size(), app)) {
        RemoveTree(app);
        if (mutex) ReleaseMutex(mutex);
        return Fail(L"cannot unpack " + self);
      }
      WriteWhole(complete, nullptr, 0);
    }
    if (mutex) {
      ReleaseMutex(mutex);
      CloseHandle(mutex);
    }
  }
  CloseHandle(file);

  std::wstring resources = app + L"\\Contents\\Resources";
  std::wstring path = app + L"\\Contents\\Libs";
  std::wstring inherited = Variable(L"PATH");
  if (!inherited.empty()) path += L";" + inherited;
  SetEnvironmentVariableW(L"PATH", path.c_str());
  SetEnvironmentVariableW(L"PYTHONPATH", (resources + L"\\python").c_str());
  SetEnvironmentVariableW(L"PYTHONNOUSERSITE", L"1");
  SetEnvironmentVariableW(L"PYTHONSAFEPATH", L"1");
  SetEnvironmentVariableW(L"PYTHONHOME", nullptr);
  SetEnvironmentVariableW(L"RUNFILES_DIR", nullptr);
  SetEnvironmentVariableW(L"RUNFILES_MANIFEST_FILE", nullptr);

  std::wstring program = Backslashed(app + L"\\", trailer.program);
  std::string bootstrap = "import runpy, sys\nsys.argv[:2] = sys.argv[1:2]\nrunpy._run_module_as_main(\"" +
                          trailer.module + "\", alter_argv=False)";
  std::wstring command = Quote(program) + L" -c " + Quote(Widen(bootstrap)) + L" " + Quote(name);
  std::wstring forwarded = Forwarded();
  if (!forwarded.empty()) command += L" " + forwarded;

  SetConsoleCtrlHandler(LeaveToTheChild, TRUE);
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (!CreateProcessW(program.c_str(), command.data(), nullptr, nullptr, TRUE, 0, nullptr, nullptr, &startup,
                      &process)) {
    return Fail(L"cannot start " + program);
  }
  CloseHandle(process.hThread);
  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(process.hProcess, &code);
  CloseHandle(process.hProcess);
  return static_cast<int>(code);
}
