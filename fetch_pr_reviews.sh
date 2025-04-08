#!/bin/bash

# Parse command line arguments for debug mode
DEBUG_MODE=false
GITHUB_USER_ARG=""
START_DATE_ARG=""
END_DATE_ARG=""
THRESHOLD_ARG=""
VERBOSE=false
MAX_PAGES=10  # Set a reasonable limit to avoid excessive API calls

# Parse command-line arguments
while getopts "du:s:e:t:vp:" opt; do
  case ${opt} in
    d ) DEBUG_MODE=true ;;
    u ) GITHUB_USER_ARG=$OPTARG ;;
    s ) START_DATE_ARG=$OPTARG ;;
    e ) END_DATE_ARG=$OPTARG ;;
    t ) THRESHOLD_ARG=$OPTARG ;;
    v ) VERBOSE=true ;;
    p ) MAX_PAGES=$OPTARG ;;
    \? ) echo "Usage: $0 [-d] [-u github_user] [-s start_date] [-e end_date] [-t threshold] [-v] [-p max_pages]" 
         echo "-d: debug mode (non-interactive)"
         echo "-u: GitHub username"
         echo "-s: start date (YYYY-MM-DD)"
         echo "-e: end date (YYYY-MM-DD)"
         echo "-t: comment threshold"
         echo "-v: verbose mode (show debug info)"
         echo "-p: maximum number of pages to fetch (default: 10)"
         exit 1 ;;
  esac
done

# Get your GitHub username
if [ -z "$GITHUB_USER_ARG" ]; then
  GITHUB_USER=$(gh api user | jq -r '.login')
  echo "Current authenticated GitHub user: $GITHUB_USER"

  # Ask if user wants to use a different username
  if [ "$DEBUG_MODE" = false ]; then
    read -p "Do you want to analyze a different GitHub user? (y/N): " change_user
    if [[ "$change_user" =~ ^[Yy]$ ]]; then
      read -p "Enter GitHub username: " input_user
      GITHUB_USER=$input_user
    fi
  fi
else
  GITHUB_USER=$GITHUB_USER_ARG
fi
echo "Analyzing GitHub user: $GITHUB_USER"

# Get date range from user
if [ -z "$START_DATE_ARG" ] || [ -z "$END_DATE_ARG" ]; then
  if [ "$DEBUG_MODE" = false ]; then
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
  else
    # Default dates for debug mode
    START_DATE=$(date -v-6m +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)
  fi
else
  START_DATE=$START_DATE_ARG
  END_DATE=$END_DATE_ARG
fi
echo "Date range: $START_DATE to $END_DATE"

# Get comment threshold from user
if [ -z "$THRESHOLD_ARG" ]; then
  if [ "$DEBUG_MODE" = false ]; then
    read -p "Minimum number of comments to consider significant [default: 5]: " threshold
    if [ -z "$threshold" ]; then
      threshold=5
    fi
  else
    threshold=5
  fi
else
  threshold=$THRESHOLD_ARG
fi
echo "Comment threshold: >$threshold"

# Create directory for data if it doesn't exist
mkdir -p pr_data

# Temp file for storing all nodes
TMP_ALL_NODES=$(mktemp)
TMP_CURRENT_PAGE=$(mktemp)

# Function to clean up temp files on exit
cleanup() {
  rm -f "$TMP_ALL_NODES" "$TMP_CURRENT_PAGE"
}
trap cleanup EXIT

# Fetch all reviews you've made
echo "Fetching PR reviews for $GITHUB_USER between $START_DATE and $END_DATE..."

# Initialize cursor for pagination
CURSOR=""
PAGE=1
TOTAL_PRS=0

while [ $PAGE -le $MAX_PAGES ]; do
  CURSOR_PARAM=""
  if [ ! -z "$CURSOR" ]; then
    CURSOR_PARAM=", after: \"$CURSOR\""
  fi

  # Add date range to the query to help with filtering
  # Note: The reviewed-by: qualifier doesn't accept date ranges, so we're adding it to the general search
  gh api graphql -f query='
  query {
    search(query: "reviewed-by:'$GITHUB_USER' updated:'$START_DATE'..'$END_DATE'", type: ISSUE, first: 100'"$CURSOR_PARAM"') {
      issueCount
      edges {
        cursor
        node {
          ... on PullRequest {
            number
            title
            url
            createdAt
            updatedAt
            closedAt
            state
            author {
              login
            }
            repository {
              nameWithOwner
            }
            reviews(first: 100, author: "'$GITHUB_USER'") {
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
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
  ' > "$TMP_CURRENT_PAGE"

  # Get the total issue count
  if [ $PAGE -eq 1 ]; then
    TOTAL_PRS=$(jq '.data.search.issueCount' "$TMP_CURRENT_PAGE")
    echo "Total PRs found: $TOTAL_PRS"
    
    # Calculate required pages
    REQUIRED_PAGES=$(( ($TOTAL_PRS + 99) / 100 ))
    echo "Required pages to fetch all results: $REQUIRED_PAGES (fetching up to $MAX_PAGES)"
  fi

  # Extract nodes and append to all_nodes
  jq -r '.data.search.edges[].node' "$TMP_CURRENT_PAGE" >> "$TMP_ALL_NODES"

  # Check if there are more pages
  HAS_NEXT_PAGE=$(jq '.data.search.pageInfo.hasNextPage' "$TMP_CURRENT_PAGE")
  
  if [ "$VERBOSE" = true ]; then
    echo "Fetched page $PAGE with $(jq '.data.search.edges | length' "$TMP_CURRENT_PAGE") results"
  fi
  
  if [ "$HAS_NEXT_PAGE" = "true" ]; then
    CURSOR=$(jq -r '.data.search.pageInfo.endCursor' "$TMP_CURRENT_PAGE")
    PAGE=$((PAGE + 1))
  else
    break
  fi
done

NODE_COUNT=$(cat "$TMP_ALL_NODES" | wc -l | tr -d ' ')
echo "Fetched $PAGE page(s) with a total of $NODE_COUNT PR nodes"

if [ "$VERBOSE" = true ]; then
  echo "Sample node data (first node):"
  head -n 30 "$TMP_ALL_NODES" | jq '.'
fi

# Process the JSON to find PRs with significant comments from you
echo "Processing results to filter PRs with significant comments from you..."

# Extract and format the review data with date filtering directly to the final files
cat "$TMP_ALL_NODES" | jq -c --arg start "$START_DATE" --arg end "$END_DATE" '
select(.reviews != null and .reviews.totalCount > 0) |
select(.reviews.nodes | map(select(.createdAt >= $start and .createdAt <= $end + "T23:59:59Z")) | length > 0) |
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
  commentCount: (if .reviews.nodes then ([.reviews.nodes[] | select(.createdAt >= $start and .createdAt <= $end + "T23:59:59Z") | .comments.totalCount]) | add else 0 end),
  lastReviewDate: (if .reviews.nodes then ([.reviews.nodes[] | select(.createdAt >= $start and .createdAt <= $end + "T23:59:59Z")] | sort_by(.createdAt) | last.createdAt) else null end)
}' | jq -s 'sort_by(.commentCount) | reverse' > pr_data/all_reviews.json

# Keep track of the filtered PR count
FILTERED_PR_COUNT=$(jq '. | length' pr_data/all_reviews.json)
if [ "$VERBOSE" = true ]; then
  echo "PRs after date filtering: $FILTERED_PR_COUNT"
fi

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
echo "Total PRs reviewed: $FILTERED_PR_COUNT"
echo "PRs with significant comments (>$threshold): $(jq '. | length' pr_data/significant_reviews.json)"
echo "Total comments across all reviews: $(jq '. | map(.commentCount) | add' pr_data/all_reviews.json)"
echo "Average comments per PR: $(jq '. | map(.commentCount) | add / length' pr_data/all_reviews.json)"

# Generate CSV file for easier analysis
echo "repo,number,title,author,state,createdAt,closedAt,reviewCount,commentCount,url" > pr_data/significant_reviews.csv
jq -r '.[] | [.repo, .number, .title, .author, .state, .createdAt, .closedAt, .reviewCount, .commentCount, .url] | @csv' pr_data/significant_reviews.json >> pr_data/significant_reviews.csv

echo "CSV file generated at pr_data/significant_reviews.csv"
