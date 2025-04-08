#!/bin/bash

# Get your GitHub username
GITHUB_USER=$(gh api user | jq -r '.login')
echo "Current authenticated GitHub user: $GITHUB_USER"

# Ask if user wants to use a different username
read -p "Do you want to analyze a different GitHub user? (y/N): " change_user
if [[ "$change_user" =~ ^[Yy]$ ]]; then
  read -p "Enter GitHub username: " input_user
  GITHUB_USER=$input_user
fi
echo "Analyzing GitHub user: $GITHUB_USER"

# Get date range from user
echo "Enter date range for PR reviews (format: YYYY-MM-DD)"
read -p "Start date [default: 6 months ago]: " input_start
read -p "End date [default: today]: " input_end

# Set default values if not provided
if [ -z "$input_start" ]; then
  # Default to 6 months ago
  START_DATE=$(date -v-6m +%Y-%m-%d)
else
  START_DATE=$input_start
fi

if [ -z "$input_end" ]; then
  # Default to today
  END_DATE=$(date +%Y-%m-%d)
else
  END_DATE=$input_end
fi

echo "Date range: $START_DATE to $END_DATE"

# Get comment threshold from user
read -p "Minimum number of comments to consider significant [default: 5]: " threshold
if [ -z "$threshold" ]; then
  threshold=5
fi
echo "Comment threshold: >$threshold"

# Create directory for data if it doesn't exist
mkdir -p pr_data

# Fetch all reviews you've made
echo "Fetching PR reviews for $GITHUB_USER between $START_DATE and $END_DATE..."

# Use GraphQL to fetch your reviews
gh api graphql -f query='
query {
  search(query: "reviewed-by:'$GITHUB_USER' created:'$START_DATE'..'$END_DATE'", type: ISSUE, first: 100) {
    edges {
      node {
        ... on PullRequest {
          number
          title
          url
          createdAt
          closedAt
          state
          author {
            login
          }
          repository {
            nameWithOwner
          }
          reviews(first: 50, author: "'$GITHUB_USER'") {
            totalCount
            nodes {
              createdAt
              state
              body
              comments {
                totalCount
              }
            }
          }
        }
      }
    }
  }
}
' > pr_data/reviews.json

# Process the JSON to find PRs with significant comments from you
echo "Processing results to filter PRs with significant comments from you..."

# Extract review data to a temporary file first to examine its structure
jq '.data.search.edges[].node' pr_data/reviews.json > pr_data/nodes.json

# Extract and format the review data - fixed version that checks for field existence
cat pr_data/nodes.json | jq -c '
select(.reviews != null and .reviews.totalCount > 0) |
{
  repo: (if .repository and .repository.nameWithOwner then .repository.nameWithOwner else "unknown" end),
  number: .number,
  title: .title,
  url: .url,
  author: (if .author and .author.login then .author.login else "unknown" end),
  state: .state,
  createdAt: .createdAt,
  closedAt: .closedAt,
  reviewCount: .reviews.totalCount,
  commentCount: (if .reviews.nodes then ([.reviews.nodes[].comments.totalCount] | add) else 0 end),
  lastReviewDate: (if .reviews.nodes then ([.reviews.nodes[]] | sort_by(.createdAt) | last.createdAt) else null end)
}' | jq -s 'sort_by(.commentCount) | reverse' > pr_data/all_reviews.json

# Filter for significant comments based on user threshold
jq --argjson threshold "$threshold" '[.[] | select(.commentCount > $threshold)]' pr_data/all_reviews.json > pr_data/significant_reviews.json

echo "Results saved to pr_data/significant_reviews.json"
echo ""
echo "-----------------------------------------------------"
echo "PRs with significant review comments (>$threshold) from $GITHUB_USER:"
echo "-----------------------------------------------------"

# Using a more reliable output format
jq -r '.[] | "PR #\(.number) in \(.repo)\n  Title: \(.title)\n  Author: \(.author)\n  State: \(.state)\n  Created: \(.createdAt)\n  \(.reviewCount) reviews, \(.commentCount) comments\n  URL: \(.url)\n"' pr_data/significant_reviews.json

echo ""
echo "-----------------------------------------------------"
echo "Summary of PR review activity for $GITHUB_USER:"
echo "-----------------------------------------------------"
echo "Total PRs reviewed: $(jq '. | length' pr_data/all_reviews.json)"
echo "PRs with significant comments (>$threshold): $(jq '. | length' pr_data/significant_reviews.json)"
echo "Total comments across all reviews: $(jq '. | map(.commentCount) | add' pr_data/all_reviews.json)"
echo "Average comments per PR: $(jq '. | map(.commentCount) | add / length' pr_data/all_reviews.json)"

# Generate CSV file for easier analysis
echo "repo,number,title,author,state,createdAt,closedAt,reviewCount,commentCount,url" > pr_data/significant_reviews.csv
jq -r '.[] | [.repo, .number, .title, .author, .state, .createdAt, .closedAt, .reviewCount, .commentCount, .url] | @csv' pr_data/significant_reviews.json >> pr_data/significant_reviews.csv

echo "CSV file generated at pr_data/significant_reviews.csv"
