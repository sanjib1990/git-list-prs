# GitHub PR Review Analysis

This repository contains scripts to analyze your GitHub Pull Request review activity.

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- `jq` installed for JSON processing

## Scripts

### `fetch_pr_reviews.sh`

This script fetches and analyzes your GitHub PR review activity within a specified date range.

**Features:**
- Retrieves PRs you've reviewed using GitHub's GraphQL API
- Identifies PRs with significant comments from you
- Generates detailed reports in JSON and CSV formats
- Provides summary statistics of your review activity
- Interactive prompts for customization

**Usage:**
```bash
# Make executable
chmod +x fetch_pr_reviews.sh

# Run the script
./fetch_pr_reviews.sh
```

**Interactive Options:**
When running the script, you will be prompted to:
1. Confirm or change the GitHub username to analyze
2. Specify a date range (defaults to the last 6 months)
3. Set the threshold for "significant comments" (defaults to 5)

**Output:**
- `pr_data/all_reviews.json`: All PRs you've reviewed
- `pr_data/significant_reviews.json`: PRs with comments above your threshold
- `pr_data/significant_reviews.csv`: CSV format for spreadsheet analysis

### `list_pr_links.sh`

This script extracts PR links from the analysis data, sorted by comment count.

**Usage:**
```bash
# Make executable
chmod +x list_pr_links.sh

# Run the script (must run fetch_pr_reviews.sh first)
./list_pr_links.sh
```

**Interactive Options:**
When running the script, you will be prompted to:
1. Use the existing threshold from `fetch_pr_reviews.sh` (default)
2. Or specify a new threshold to apply

**Output:**
A list of PR links with comment counts in descending order.

## Example Workflow

```bash
# Step 1: Fetch your PR review data (with interactive prompts)
./fetch_pr_reviews.sh

# Step 2: List PRs with significant comments (with optional new threshold)
./list_pr_links.sh
```

## Technical Details

- The scripts use GitHub's GraphQL API via the GitHub CLI
- JSON data is processed using `jq`
- All data is stored locally in the `pr_data` directory
- Default date calculation uses the `date` command with macOS format (`-v-6m`)
