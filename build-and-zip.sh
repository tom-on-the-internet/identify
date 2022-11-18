#!/usr/bin/env bash

# Build the application
# Remove existing zip files
# Zip it with a unique name so terraform knows it is new

# the name "bootstrap" is a special name that allows
# Amazon Linux 2 to find and run this binary.
EXECUTABLE_NAME=bootstrap

# Build the application so that it will run in AWS Lambda.
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o $EXECUTABLE_NAME .

# Clear out any previous zips so that they aren't picked up by Terraform.
rm identify*zip

# Create the zip archive with the datetime in the filename.
zip "identify-$(date -Iseconds).zip" $EXECUTABLE_NAME
