/*
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
int global;

void compare_global_variable_bad() {
  char arr[10];
  if (global < 10)
    arr[10] = 1;
}

const int global_const_zero = 0;

enum { global_const = global_const_zero };

void compare_global_const_enum_bad_FN() {
  char arr[10];
  if (global_const < 10)
    arr[10] = 1;
}
