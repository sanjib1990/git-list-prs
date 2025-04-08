# GitHub PR Review Analysis

This repository contains scripts to analyze your GitHub Pull Request review activity.

## Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- `jq` installed for JSON processing

## Setting Up GitHub CLI

GitHub CLI (`gh`) is required for these scripts to work. Follow these steps to set it up:

### Installation

#### macOS
```bash
# Using Homebrew
brew install gh

# Using MacPorts
sudo port install gh
```

#### Linux
```bash
# Debian/Ubuntu
sudo apt install gh

# Fedora
sudo dnf install gh

# Arch Linux
sudo pacman -S github-cli
```

#### Windows
```powershell
# Using Scoop
scoop install gh

# Using Chocolatey
choco install gh

# Using winget
winget install --id GitHub.cli
```

For other installation methods, see the [official documentation](https://github.com/cli/cli#installation).

### Authentication

After installing, you need to authenticate with your GitHub account:

```bash
# Start the login process
gh auth login

# Follow the interactive prompts:
# 1. Select GitHub.com (not enterprise)
# 2. Choose HTTPS protocol
# 3. Choose to authenticate with your GitHub credentials
# 4. Select login with a web browser (easiest)
```

### Verifying Installation

To verify that `gh` is properly installed and authenticated:

```bash
# Check version
gh --version

# Check if you're authenticated
gh auth status
```

### Installing jq

The scripts also require `jq` for processing JSON data:

#### macOS
```bash
brew install jq
```

#### Linux
```bash
# Debian/Ubuntu
sudo apt install jq

# Fedora
sudo dnf install jq

# Arch Linux
sudo pacman -S jq
```

#### Windows
```powershell
# Using Chocolatey
choco install jq

# Using Scoop
scoop install jq
```

## Scripts

### `fetch_pr_reviews.sh`

This script fetches and analyzes your GitHub PR review activity within a specified date range.

**Features:**
- Retrieves PRs you've reviewed using GitHub's GraphQL API
- Identifies PRs with significant comments from you
- Generates detailed reports in JSON and CSV formats
- Provides summary statistics of your review activity
- Interactive prompts for customization
- Supports pagination to fetch large result sets
- Non-interactive mode with command-line arguments for scripting

**Usage:**
```bash
# Make executable
chmod +x fetch_pr_reviews.sh

# Interactive mode (with prompts)
./fetch_pr_reviews.sh

# Non-interactive mode with command-line arguments
./fetch_pr_reviews.sh -d -u github-username -s 2024-01-01 -e 2024-12-31 -t 3 -p 5
```

**Command-line Arguments:**
```
-d: Debug/non-interactive mode
-u: GitHub username
-s: Start date (YYYY-MM-DD)
-e: End date (YYYY-MM-DD)
-t: Comment threshold
-v: Verbose mode (show debug info)
-p: Maximum number of pages to fetch (default: 10)
```

**Interactive Options:**
When running the script without arguments, you will be prompted to:
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

## Example Workflows

### Basic Analysis
```bash
# Step 1: Fetch your PR review data (with interactive prompts)
./fetch_pr_reviews.sh

# Step 2: List PRs with significant comments (with optional new threshold)
./list_pr_links.sh
```

### Automated Analysis for a Specific Date Range
```bash
# Fetch all PRs reviewed in 2024 with at least 3 comments, up to 5 pages of results
./fetch_pr_reviews.sh -d -u github-username -s 2024-01-01 -e 2024-12-31 -t 3 -p 5

# Output results to a text file
./list_pr_links.sh > pr_report.txt
```

### Debugging with Verbose Mode
```bash
# Run with verbose output to help troubleshoot issues
./fetch_pr_reviews.sh -d -v -u github-username -s 2024-01-01 -e 2024-12-31 -t 0
```

## Analysis and Post-Processing

After running the scripts, you can analyze the PR data in various ways:

1. **Filter by state (OPEN/MERGED/CLOSED)**:
   ```bash
   jq '.[] | select(.state == "MERGED" or .state == "OPEN")' pr_data/significant_reviews.json
   ```

2. **Group PRs by repository**:
   ```bash
   jq 'group_by(.repo) | map({repo: .[0].repo, prs: .})' pr_data/significant_reviews.json
   ```

3. **Find top PRs for each repository**:
   ```bash
   jq 'group_by(.repo) | map({repo: .[0].repo, prs: (. | sort_by(-.commentCount) | .[0:3])})' pr_data/significant_reviews.json
   ```

4. **Open CSV data in spreadsheet applications** for custom charts and analysis

## Technical Details

- The scripts use GitHub's GraphQL API via the GitHub CLI
- JSON data is processed using `jq`
- All data is stored locally in the `pr_data` directory
- Default date calculation uses the `date` command with macOS format (`-v-6m`)
- Pagination is implemented to handle large result sets (>100 PRs)
- Temporary files are automatically cleaned up when the script exits
