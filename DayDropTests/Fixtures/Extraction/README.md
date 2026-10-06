# Extraction recognition fixtures

`bundle.zip`, `bundle.7z`, `flat.zip`, `unicode.zip`, `unsafe.zip`,
`symlink.zip`, and `encrypted.zip` were generated for these tests. The encrypted
ZIP uses the non-secret test password `fixture-only`; the app does not prompt
for or retain passwords.

The following RAR fixtures are decoded copies of libarchive v3.7.4 test files
(commit `313aa1fa10b657de791e3202c168a6c833bc3543`):

- `sample-rar3.rar`: `libarchive/test/test_read_format_rar_windows.rar.uu`
- `sample-rar5.rar`: `libarchive/test/test_read_format_rar5_stored.rar.uu`
- `linked.rar`: `libarchive/test/test_read_format_rar.rar.uu`
- `incomplete-volume.rar`: `libarchive/test/test_read_format_rar5_multiarchive.part01.rar.uu` (first volume only)

Source: https://github.com/libarchive/libarchive/tree/v3.7.4/libarchive/test

The upstream license is included as `LICENSE.txt`. Test authors: Tim Kientzle
(2003–2007), Andres Mejia (2011), Michihiro NAKAJIMA (2011–2012), and
Grzegorz Antoniak (2018). Copyright notices and two-clause BSD terms are retained
in `LICENSE.txt`.
