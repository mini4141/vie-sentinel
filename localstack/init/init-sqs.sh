#!/bin/sh
# Runs inside LocalStack when it is ready: creates the alert queue and its DLQ.
set -e
awslocal sqs create-queue --queue-name sentinel-alerts-dlq
DLQ_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://sqs.ap-southeast-2.localhost.localstack.cloud:4566/000000000000/sentinel-alerts-dlq \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
awslocal sqs create-queue --queue-name sentinel-alerts \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\",\"MessageRetentionPeriod\":\"86400\"}"
echo "sqs queues ready"
