#!/bin/bash

# Test Suite
# A script that runs through a series of tests found in a file and confirms the results
# using an "answers" file. See included sample files for format of test and answer files.
# Run with no parameters for usage.

IFS="
"

# Parameters
SCRIPT=""
TESTS=""
ANSWERS=""
PAUSE=
ONLY_TEST=

# Parameter help
if [ $# -lt 6 ]; then
   echo "Error: Received less than six arguments. The following arguments are required:"
   echo "   --script /path/to/script"
   echo "   --tests /path/to/tests"
   echo "   --answers /path/to/answers"
   echo "The following arguments are optional:"
   echo "   --pause N, where N is a positive integer or decimal number"
   echo "   --only-test N, where N is the number of the line to run in the test suite"
   exit
fi

# Tell us if this string can be read as a positive integer
function isAnInteger()
{
   if [[ "$1" =~ ^[0-9]*$ ]]; then
      echo 1
   else
      echo 0
   fi
}

# Tell us if this string can be read as a positive integer or floating-point number
function isAFloat()
{
   if [[ "$1" =~ ^[0-9]+\.{0,1}[0-9]*$ ]]; then
      echo 1
   else
      echo 0
   fi
}

# Tell us how many line the file actually has
function countLines()
{
   # Run 'wc' and parse output for line count
   NUM_LINES=$(wc -l "$1")
   NUM_LINES=$(echo $NUM_LINES | egrep -o "[[:digit:]]* ")
   NUM_LINES=$(echo $NUM_LINES | tr -d '[:space:]')
   
   # Adjust for files that don't end in a newline, because 'wc' is dumb
   LAST_CHAR=$(tail -c -1 "$1")
   if [ "$LAST_CHAR" != "\n" ]; then
      let NUM_LINES+=1
   fi
   
   echo $NUM_LINES
}

# Process all arguments
while (( "$#" )); do
   # Shift 2 spaces unless that takes us past the end of the argument array, which
   # seems to hang the shell
   SAFE_2=2
   if [ "$#" -eq 1 ]; then
      SAFE_2=1
   fi

   case "$1" in
      --script )    SCRIPT="$2"; shift $SAFE_2;;
      --tests )     TESTS="$2"; shift $SAFE_2;;
      --answers )   ANSWERS="$2"; shift $SAFE_2;;
      --pause )     PAUSE="$2"; shift $SAFE_2;;
      --only-test ) ONLY_TEST="$2"; shift $SAFE_2;;
      * )           mypr "Error: Unrecognized argument '$1'."; exit;;
   esac
done

# Safety checks
if [ ! -f "$SCRIPT" ]; then
   echo "Error: No file found at path '$SCRIPT'!"
   exit
fi
if [ ! -f "$TESTS" ]; then
   echo "Error: No file found at path '$TESTS'!"
   exit
fi
if [ ! -f "$ANSWERS" ]; then
   echo "Error: No file found at path '$ANSWERS'!"
   exit
fi
TEST_LINES=$(countLines "$TESTS")
ANSW_LINES=$(countLines "$ANSWERS")
if [ $TEST_LINES -ne $ANSW_LINES ]; then
   echo "Error: Test and answer files are not equal length ($TEST_LINES and $ANSW_LINES respectively)."
   exit
fi
if [ ! -z "$PAUSE" ]; then
   VALID=$(isAFloat "$PAUSE")
   if [ $VALID -eq 0 ]; then
      echo "Error: Did not receive a valid number for the '--pause' argument."
      exit
   fi
else
   PAUSE=0
fi
if [ ! -z "$ONLY_TEST" ]; then
   VALID=$(isAnInteger "$ONLY_TEST")
   if [ $VALID -eq 0 ]; then
      echo "Error: Did not receive a valid number for the '--only-test' argument."
      exit
   fi
   if [ $ONLY_TEST -gt $TEST_LINES ]; then
      echo "Error: Received request to run test $ONLY_TEST, but test file is only $TEST_LINES lines long."
      exit
   fi
else
   ONLY_TEST=0
fi

# Print running parameters
echo
if [ $ONLY_TEST -eq 0 ]; then
   echo "Running test suite…"
else
   echo "Running only test $ONLY_TEST in test suite…"
fi
echo $TESTS
echo "…and comparing against results file…"
echo $ANSWERS
if [ $(echo $PAUSE'>'0 | bc -l) -eq 1 ]; then
   echo "…with $PAUSE second pause between tests."
fi
echo

# Start test suite
i=1
if [ $ONLY_TEST -gt 0 ]; then
   i=$ONLY_TEST
fi
for ((; i <= $TEST_LINES; ++i)); do
   TEST_LINE=$(tail -n+$i $TESTS | head -n1)
   ANSWER_LINE=$(tail -n+$i $ANSWERS | head -n1)
   echo -n "Running test $i..."
   if [[ "$ANSWER_LINE" =~ ^err:* ]]; then # compare error code to expected one
      EXP_ERR=${ANSWER_LINE#*err:}
      
      # Run test
      eval "bash \"$SCRIPT\" $TEST_LINE &> /dev/null"
      REC_ERR=$?
      
      # Print results
      if [ $REC_ERR -eq $EXP_ERR ]; then
         echo " passed."
      else
         echo " failed. Received error $REC_ERR instead of expected error $EXP_ERR."
         exit
      fi
   elif [[ "$ANSWER_LINE" =~ ^lines:* ]]; then # confirm that we received the expected amount of output
      EXP_LINES=${ANSWER_LINE#*lines:}
      
      # Run test
      STD_OUT=$(eval "bash \"$SCRIPT\" $TEST_LINE 2> /dev/null")
      OUT_LINES=$(echo "$STD_OUT" | wc -l | tr -d '[:space:]')
      
      # Print results
      STR_LINES="lines"
      if [ $OUT_LINES -eq 1 ]; then
         STR_LINES="line"
      fi
      if [ $OUT_LINES -eq $EXP_LINES ]; then
         echo " passed."
      else
         echo " failed. Received $OUT_LINES $STR_LINES of output instead of expected $EXP_LINES."
         exit
      fi
   elif [[ "$ANSWER_LINE" =~ ^compfile:* ]]; then # confirm that script's output is what we expected
      COMP_FILE=${ANSWER_LINE#*compfile:}
      COMP_FILE_TEXT=$(cat "$COMP_FILE")
      
      # Run test
      STD_OUT=$(eval "bash \"$SCRIPT\" $TEST_LINE 2> /dev/null")
      
      # Print results
      if [ "$STD_OUT" == "$COMP_FILE_TEXT" ]; then
         echo " passed."
      else
         echo " failed. Received this as output: '$STD_OUT'."
         exit
      fi
   elif [[ "$ANSWER_LINE" =~ ^compfolder:* ]]; then # check results of batch operation against reference
      # Make temp folder for holding comp, source and output folders
      TEMP_DIR=$(mktemp -d)
      THE_TIME=$(date "+%Y-%m-%d--%H-%M-%S")
      NEW_DIR="$TEMP_DIR/TestSuite testbed ($THE_TIME)"
      mkdir "$NEW_DIR"
      
      # Get comp folder path, unzip it to temp dir if it's a ZIP
      COMP_FOLD=${ANSWER_LINE#*compfolder:}
      COMP_FOLD=${COMP_FOLD%%|*}
      COMP_SUFF=${COMP_FOLD##*.}
      if [ "$COMP_SUFF" == "zip" ]; then
         if [ ! -f "$COMP_FOLD" ]; then
            echo "Error: Could not find a file at the path $COMP_FOLD."
            exit
         else
            unzip "$COMP_FOLD" -d "$NEW_DIR/Comp" 1> /dev/null
            COMP_FOLD="$NEW_DIR/Comp"
         fi
      else
         if [ ! -d "$COMP_FOLD" ]; then
            echo "Error: Could not find a folder at the path $COMP_FOLD."
            exit
         else
            cp -R "$COMP_FOLD/" "$NEW_DIR/Comp"
         fi
      fi
      
      # Get source folder path, unzip it to temp dir if it's a ZIP
      SRC_FOLD=${ANSWER_LINE#*|srcfolder:}
      SRC_FOLD=${SRC_FOLD%%|*}
      SRC_SUFF=${SRC_FOLD##*.}
      if [ "$SRC_SUFF" == "zip" ]; then
         if [ ! -f "$SRC_FOLD" ]; then
            echo "Error: Could not find a file at the path $SRC_FOLD."
            exit
         else
            unzip "$SRC_FOLD" -d "$NEW_DIR/Source" 1> /dev/null
            SRC_FOLD="$NEW_DIR/Source"
         fi
      else
         if [ ! -d "$SRC_FOLD" ]; then
            echo "Error: Could not find a folder at the path $SRC_FOLD."
            exit
         else
            cp -R "$SRC_FOLD/" "$NEW_DIR/Source"
         fi
      fi
      
      # Get comparison method, if present, or default to checksum comparison
      COMP_METHOD="cksum"
      if [[ "$ANSWER_LINE" =~ method ]]; then
         CUST_METHOD=${ANSWER_LINE#*|method:}
         if [ "$CUST_METHOD" == "size" ]; then
            COMP_METHOD=$CUST_METHOD
         elif [ ! "$CUST_METHOD" == "cksum" ]; then
            echo "Error: Unknown requested comparison method '$CUST_METHOD'. Your choices are 'cksum' and 'size'."
            exit
         fi
      fi
      
      # Replace "[SOURCE]" in the test line with the path to our copy of the source data
      NEW_TEST_LINE=$(echo $TEST_LINE | sed "s:\[SOURCE\]:\"$SRC_FOLD\":")
      
      # If "[OUTPUT]" exists in the test line, replace it with the path to a newly made
      # Output folder, otherwise use Test as the output folder because the operation is
      # being done in-place on the source files
      OUT_FOLD="$SRC_FOLD"
      if [[ "$TEST_LINE" =~ \[OUTPUT\] ]]; then
         OUT_FOLD="$NEW_DIR/Output"
         mkdir "$OUT_FOLD"
         NEW_TEST_LINE=$(echo $NEW_TEST_LINE | sed "s:\[OUTPUT\]:\"$OUT_FOLD\":")
      fi
      
      # Run test
      STD_OUT=$(eval "bash \"$SCRIPT\" $NEW_TEST_LINE &> /dev/null")
      
      # Check output folder against comp folder
      FAILED_FIND=0
      FAILED_MD5=0
      FAILED_SIZE=0
      for FILE_C in `find $COMP_FOLD -type f -a ! -name ".DS_Store"`; do
         # Construct equivalent file path in OUT_FOLD
	      FILE_T=${FILE_C#$COMP_FOLD}
	      FILE_T=${OUT_FOLD}${FILE_T}
	      
	      # If there is no such file in OUT_FOLD, exit the loop
	      if [ ! -f "$FILE_T" ]; then
	         FAILED_FIND=1
	         break
	      else
	         if [ $COMP_METHOD == "cksum" ]; then
               MD1=$(md5 "$FILE_C" | grep -o "\b[[:alnum:]]*$")
               MD2=$(md5 "$FILE_T" | grep -o "\b[[:alnum:]]*$")
               if [ $MD1 != $MD2 ]; then
                  FAILED_MD5=1
                  break
               fi
            else
               SIZE1=$(stat -s "$FILE_C")
               SIZE1=${SIZE1#*st_size=*}
               SIZE1=${SIZE1%% *}
               SIZE2=$(stat -s "$FILE_T")
               SIZE2=${SIZE2#*st_size=*}
               SIZE2=${SIZE2%% *}
               if [ $SIZE1 != $SIZE2 ]; then
                  FAILED_SIZE=1
                  break
               fi
			   fi
	      fi
      done
      
      # Print results
      if [ $FAILED_FIND -eq 1 ]; then
         echo " failed. Did not find file ${FILE_C#$COMP_FOLD} in test output and stopped checking results."
         exit
      elif [ $FAILED_MD5 -eq 1 ]; then
         echo " failed. Got checksum mismatch with ${FILE_C#$COMP_FOLD} ($MD1 vs. $MD2) and stopped checking results."
         exit
      elif [ $FAILED_SIZE -eq 1 ]; then
         echo " failed. Got size mismatch with ${FILE_C#$COMP_FOLD} ($SIZE1 vs. $SIZE2) and stopped checking results."
         exit
      else
         echo " passed."
      fi
   else
      echo "Error: Unknown result instruction '$ANSWER_LINE'."
   fi
   if [ $ONLY_TEST -gt 0 ]; then
      exit
   fi
   sleep $PAUSE
done
echo "All tests were successfully executed!"