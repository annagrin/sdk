// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class _StorageJs extends _DOMTypeJs implements Storage native "*Storage" {

  final int length;

  void clear() native;

  String getItem(String key) native;

  String key(int index) native;

  void removeItem(String key) native;

  void setItem(String key, String data) native;


  // Storage needs a special implementation of dartObjectLocalStorage since it
  // captures what would normally be an expando and places property in the
  // storage, stringifying the assigned value.

  var get dartObjectLocalStorage() native """
    if (this === window.localStorage)
      return window._dartLocalStorageLocalStorage;
    else if (this === window.sessionStorage)
      return window._dartSessionStorageLocalStorage;
    else
      throw new UnsupportedOperationException('Cannot dartObjectLocalStorage for unknown Storage object.');
""" { throw new UnsupportedOperationException(''); }

  void set dartObjectLocalStorage(var value) native """
    if (this === window.localStorage)
      window._dartLocalStorageLocalStorage = value;
    else if (this === window.sessionStorage)
      window._dartSessionStorageLocalStorage = value;
    else
      throw new UnsupportedOperationException('Cannot dartObjectLocalStorage for unknown Storage object.');
""" { throw new UnsupportedOperationException(''); }
}
