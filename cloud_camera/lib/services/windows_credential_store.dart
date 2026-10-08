import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsCredentialStore {
  static const _targetName = 'CloudCamera.GoogleDrive.RefreshToken';

  String? readRefreshToken() {
    if (!Platform.isWindows) return null;
    return using((arena) {
      final credentialPointer = arena<Pointer<CREDENTIAL>>();
      final targetName = arena.pcwstr(_targetName);
      try {
        final result = CredRead(
          targetName,
          CRED_TYPE_GENERIC,
          credentialPointer,
        );
        if (!result.value) {
          if (result.error == ERROR_NOT_FOUND) return null;
          throw WindowsException(result.error.toHRESULT());
        }
        final credential = credentialPointer.value.ref;
        final bytes = credential.CredentialBlob.asTypedList(
          credential.CredentialBlobSize,
        );
        return utf8.decode(bytes);
      } finally {
        if (!credentialPointer.value.isNull) {
          CredFree(credentialPointer.value);
        }
      }
    });
  }

  void saveRefreshToken(String refreshToken) {
    if (!Platform.isWindows) return;
    using((arena) {
      final tokenBytes = utf8.encode(refreshToken);
      final credential = arena<CREDENTIAL>();
      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = arena.pwstr(_targetName)
        ..Persist = CRED_PERSIST_LOCAL_MACHINE
        ..UserName = arena.pwstr('Google Drive')
        ..CredentialBlob = tokenBytes.toNative(allocator: arena)
        ..CredentialBlobSize = tokenBytes.length;
      final result = CredWrite(credential, 0);
      if (!result.value) {
        throw WindowsException(result.error.toHRESULT());
      }
    });
  }

  void deleteRefreshToken() {
    if (!Platform.isWindows) return;
    using((arena) {
      final result = CredDelete(arena.pcwstr(_targetName), CRED_TYPE_GENERIC);
      if (!result.value && result.error != ERROR_NOT_FOUND) {
        throw WindowsException(result.error.toHRESULT());
      }
    });
  }
}
