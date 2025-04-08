#!/bin/bash

# Check if significant_reviews.json exists
if [ ! -f "pr_data/significant_reviews.json" ]; then
  echo "Error: pr_data/significant_reviews.json not found."
  echo "Please run fetch_pr_reviews.sh first."
  exit 1
fi

# Get the threshold from user input
read -p "Minimum number of comments to show [default: use existing filter]: " threshold

if [ -z "$threshold" ]; then
  # Use the already filtered significant_reviews.json
  echo "Using pre-filtered results from significant_reviews.json:"
  jq -r 'sort_by(-.commentCount) | .[] | "\(.commentCount) comments: \(.url)"' pr_data/significant_reviews.json
else
  # Apply new threshold to all_reviews.json
  echo "Showing PRs with more than $threshold comments:"
  
  # Check if all_reviews.json exists
  if [ ! -f "pr_data/all_reviews.json" ]; then
    echo "Error: pr_data/all_reviews.json not found."
    echo "Please run fetch_pr_reviews.sh first."
    exit 1
  fi
  
  jq -r --argjson threshold "$threshold" 'map(select(.commentCount > $threshold)) | sort_by(-.commentCount) | .[] | "\(.commentCount) comments: \(.url)"' pr_data/all_reviews.json
fi
