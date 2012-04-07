#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Downloads the 20newsgroups dataset, trains and tests a classifier.
# Rani: add cbayes
#
# To run:  change into the mahout directory and type:
#  examples/bin/build-20news.sh

# Rani: set HADOOP_HOME to "", so we won't be dependent on Hadoop
HADOOP_HOME=""

if [ "$1" = "--help" ] || [ "$1" = "--?" ]; then
  echo "This script runs SGD and Bayes classifiers over the classic 20 News Groups."
  exit
fi

SCRIPT_PATH=${0%/*}
if [ "$0" != "$SCRIPT_PATH" ] && [ "$SCRIPT_PATH" != "" ]; then 
  cd $SCRIPT_PATH
fi
START_PATH=`pwd`

WORK_DIR=/tmp/mahout-work-${USER}

# Rani: added cbayes

algorithm=( naivebayes cbayes sgd clean)
if [ -n "$1" ]; then
  choice=$1
else
  echo "Please select a number to choose the corresponding task to run"
  echo "1. ${algorithm[0]}"
  echo "2. ${algorithm[1]}"
  echo "3. ${algorithm[2]}"
  echo "4. ${algorithm[3]} -- cleans up the work area in $WORK_DIR"
  read -p "Enter your choice : " choice
fi

echo "ok. You chose $choice and we'll use ${algorithm[$choice-1]}"
alg=${algorithm[$choice-1]}

# Rani: add ngram
echo "Please select an ngram size"
read -p "Enter your ngram size (1 or 2): " ngram
echo "ok. You chose ngram=$ngram"
if [ $ngram > 2 ]; then 
	echo "Warning: setting ngram above 2 will be sloooowwww"
fi

echo "creating work directory at ${WORK_DIR}"

mkdir -p ${WORK_DIR}
if [ ! -e ${WORK_DIR}/20news-bayesinput ]; then
  if [ ! -e ${WORK_DIR}/20news-bydate ]; then
    if [ ! -f ${WORK_DIR}/20news-bydate.tar.gz ]; then
      echo "Downloading 20news-bydate"
      curl http://people.csail.mit.edu/jrennie/20Newsgroups/20news-bydate.tar.gz -o ${WORK_DIR}/20news-bydate.tar.gz
    fi
    mkdir -p ${WORK_DIR}/20news-bydate
    echo "Extracting..."
    cd ${WORK_DIR}/20news-bydate && tar xzf ../20news-bydate.tar.gz && cd .. && cd ..
  fi
fi
#echo $START_PATH
cd $START_PATH
cd ../..

set -e

# Rani: added bayestype
if [ "x$alg" == "xnaivebayes" ]; then
	bayestype="bayes"
fi

if [ "x$alg" == "xcbayes" ]; then
	bayestype="cbayes"
	echo "Rani" $bayestype
fi
   
if [ "x$alg" == "xnaivebayes" ] || [ "x$alg" == "xcbayes" ]; then
  echo "Preparing Training Data"
  ./bin/mahout org.apache.mahout.classifier.bayes.PrepareTwentyNewsgroups \
    -p ${WORK_DIR}/20news-bydate/20news-bydate-train \
    -o ${WORK_DIR}/20news-bydate/bayes-train-input \
    -a org.apache.mahout.vectorizer.DefaultAnalyzer \
    -c UTF-8

  echo "Preparing Test Data"

  ./bin/mahout org.apache.mahout.classifier.bayes.PrepareTwentyNewsgroups \
    -p ${WORK_DIR}/20news-bydate/20news-bydate-test \
    -o ${WORK_DIR}/20news-bydate/bayes-test-input \
    -a org.apache.mahout.vectorizer.DefaultAnalyzer \
    -c UTF-8

  TEST_METHOD="sequential"

  # if we're set up to run on a cluster..
  if [ "$HADOOP_HOME" != "" ]; then
      # mapreduce test method used on hadoop
      TEST_METHOD="mapreduce"

      set +e
      hadoop dfs -rmr \
        ${WORK_DIR}/20news-bydate/bayes-train-input

      hadoop dfs -rmr \
        ${WORK_DIR}/20news-bydate/bayes-test-input

      set -e
      hadoop dfs -put \
        ${WORK_DIR}/20news-bydate/bayes-train-input \
        ${WORK_DIR}/20news-bydate/bayes-train-input

      hadoop dfs -put \
        ${WORK_DIR}/20news-bydate/bayes-test-input \
        ${WORK_DIR}/20news-bydate/bayes-test-input
  fi
  
  ./bin/mahout trainclassifier \
    -i ${WORK_DIR}/20news-bydate/bayes-train-input \
    -o ${WORK_DIR}/20news-bydate/bayes-model \
    -type $bayestype \
    -ng $ngram \
    -source hdfs

  ./bin/mahout testclassifier \
    -m ${WORK_DIR}/20news-bydate/bayes-model \
    -d ${WORK_DIR}/20news-bydate/bayes-test-input \
    -type $bayestype \
    -ng $ngram \
    -source hdfs \
    -method ${TEST_METHOD}
elif [ "x$alg" == "xsgd" ]; then
  if [ ! -e "/tmp/news-group.model" ]; then
    echo "Training on ${WORK_DIR}/20news-bydate/20news-bydate-train/"
    ./bin/mahout org.apache.mahout.classifier.sgd.TrainNewsGroups ${WORK_DIR}/20news-bydate/20news-bydate-train/
  fi
  echo "Testing on ${WORK_DIR}/20news-bydate/20news-bydate-test/ with model: /tmp/news-group.model"
  ./bin/mahout org.apache.mahout.classifier.sgd.TestNewsGroups --input ${WORK_DIR}/20news-bydate/20news-bydate-test/ --model /tmp/news-group.model
elif [ "x$alg" == "xclean" ]; then
  rm -rf ${WORK_DIR}
  rm -rf /tmp/news-group.model
fi
# Remove the work directory
#
