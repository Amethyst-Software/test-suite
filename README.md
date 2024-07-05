# TestSuite
This script runs through a series of tests that the user provides in one file and confirms each result using a set of "answers" provided in a second file.

The usage documentation for the script itself can be seen by running TestSuite without any arguments. The format of the "test suite" and "answer sheet" passed with the "--tests" and "--answers" parameters is plain-text with each test item separated by a newline, as seen in the sample files.

Here are the types of test results you can instruct TestSuite to expect:
- err:NUM
  - The test command should return error code NUM.
- lines:NUM
  - The test command should return NUM lines of output.
- compfile:/path/to/file.txt
  - The test command should return the exact output found in file.txt.
- compfolder:/path/to/folder_or_zip|srcfolder:/path/to/other/folder_or_zip
  - The test command will be run on the source folder of files specified by 'srcfolder:' and the outputted files will have their checksums compared to the corresponding files in the comparison folder specified by 'compfolder:'. If either path leads to a zipped folder of files, it will be expanded first. Add "|method:size" to the end of the test command and it will compare files by exact size instead of checksum.

Special keywords [SOURCE] and [OUTPUT]: If you use compfolder as the expected result for an operation that your script will be performing on a set of files, you cannot know what the source directory for the operation will be at test-time. This is because a ZIP listed as the source or comparison folder will have to be expanded somewhere, so TestSuite creates a temporary folder and either expands the ZIP there or, if an unzipped folder was specified, copies its contents to the same temp directory for the sake of consistency with how ZIPs are handled. Therefore you should write "[SOURCE]" on the test line where the input directory is passed to your script, and this will be substituted at test-time for the temp dir that contains those source files. Likewise, if your script's output directory is not the same as the source directory and needs to be specified separately, write "[OUTPUT]" on the test line and TestSuite will plug in the temporary output directory when it runs the test.

![Preview](https://github.com/Amethyst-Software/test-suite/blob/main/preview.png)