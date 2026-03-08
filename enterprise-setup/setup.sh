#!/usr/bin/env bash
#===============================================================================
# Enterprise GitHub Repository Setup Script
# TUI-based interactive and non-interactive setup for enterprise-grade repos
#===============================================================================

set -euo pipefail

# Version
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration defaults
DEFAULT_REPO_NAME=""
DEFAULT_REPO_DESCRIPTION=""
DEFAULT_LICENSE="MIT"
DEFAULT_AUTHOR=""
DEFAULT_GH_USERNAME=""
AUTO_DETECT=true
INTERACTIVE=true

# Feature flags
FEATURE_COMMITLINT=true
FEATURE_STANDARD_VERSION=true
FEATURE_HUSKY=true
FEATURE_BRANCH_PROTECTION=true
FEATURE_PR_TEMPLATE=true
FEATURE_ISSUE_TEMPLATES=true
FEATURE_GITIGNORE=true
FEATURE_README=true
FEATURE_SECURITY=true
FEATURE_DISCUSSIONS=true
FEATURE_CI=true

#===============================================================================
# Utility Functions
#===============================================================================

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

print_header() {
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo -e "${BOLD}${CYAN} Enterprise GitHub Setup v${VERSION}${NC}"
    echo -e "${BOLD}${CYAN}========================================${NC}"
    echo ""
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --repo-name NAME          Repository name"
    echo "  --description DESC        Repository description"
    echo "  --author NAME             Author name"
    echo "  --gh-username USER        GitHub username"
    echo "  --license LICENSE        License (MIT, Apache-2.0, GPL-3.0, BSD-3-Clause)"
    echo "  --no-interactive         Run in non-interactive mode"
    echo "  --detect/--no-detect     Auto-detect git config (default: detect)"
    echo ""
    echo "Feature Flags (default: all enabled):"
    echo "  --[no-]commitlint        Conventional commits"
    echo "  --[no-]versioning        Auto versioning (standard-version)"
    echo "  --[no-]husky             Git hooks"
    echo "  --[no-]branch-protection Branch protection rules"
    echo "  --[no-]pr-template       PR template"
    echo "  --[no-]issue-templates   Issue templates"
    echo "  --[no-]gitignore        Generate .gitignore"
    echo "  --[no-]readme           Generate README"
    echo "  --[no-]security         Security policy"
    echo "  --[no-]discussions      Discussions setup"
    echo "  --[no-]ci               CI/CD workflows"
    echo ""
    echo "  --all                    Enable all features"
    echo "  --defaults               Use defaults without prompting"
    echo ""
    echo "Examples:"
    echo "  $0 --repo-name my-app --description 'My awesome app'"
    echo "  $0 --no-interactive --all"
    echo "  $0 --defaults --no-husky"
    exit 0
}

#===============================================================================
# Auto Detection
#===============================================================================

detect_git_config() {
    if [ -d ".git" ]; then
        DEFAULT_AUTHOR=$(git config user.name 2>/dev/null || echo "")
        DEFAULT_GH_USERNAME=$(git config user.email 2>/dev/null | sed 's/@.*//' || echo "")
        
        if [ -n "$DEFAULT_AUTHOR" ]; then
            log_info "Detected git user.name: $DEFAULT_AUTHOR"
        fi
        if [ -n "$DEFAULT_GH_USERNAME" ]; then
            log_info "Detected git user.email prefix: $DEFAULT_GH_USERNAME"
        fi
    fi
    
    # Try to get GitHub username from gh cli
    if command -v gh &>/dev/null; then
        GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
        if [ -n "$GH_USER" ]; then
            DEFAULT_GH_USERNAME="$GH_USER"
            log_info "Detected GitHub username: $GH_USER"
        fi
    fi
    
    # Try to get from current directory
    if [ -z "$DEFAULT_REPO_NAME" ]; then
        DEFAULT_REPO_NAME=$(basename "$(pwd)")
        log_info "Detected repo name: $DEFAULT_REPO_NAME"
    fi
}

#===============================================================================
# Interactive TUI
#===============================================================================

prompt() {
    local prompt="$1"
    local default="$2"
    local result
    
    if [ -n "$default" ]; then
        echo -en "${YELLOW}${prompt}${NC} [$default]: "
    else
        echo -en "${YELLOW}${prompt}${NC}: "
    fi
    
    read -r result
    
    if [ -z "$result" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$result"
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    local yn
    if [ "$default" = "y" ]; then
        echo -en "${YELLOW}${prompt} [Y/n]: ${NC}"
        read -r yn
        [ -z "$yn" ] && yn="y"
    else
        echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
        read -r yn
        [ -z "$yn" ] && yn="n"
    fi
    
    [[ "$yn" =~ ^[Yy]$ ]]
}

show_menu() {
    local title="$1"
    shift
    local options=("$@")
    local num=${#options[@]}
    
    echo -e "${BOLD}${CYAN}$title${NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    echo ""
}

interactive_setup() {
    print_header
    
    log_info "Let's set up your enterprise repository!"
    echo ""
    
    # Basic info
    DEFAULT_REPO_NAME=$(prompt "Repository name" "$DEFAULT_REPO_NAME")
    DEFAULT_REPO_DESCRIPTION=$(prompt "Description" "$DEFAULT_REPO_DESCRIPTION")
    DEFAULT_AUTHOR=$(prompt "Author name" "$DEFAULT_AUTHOR")
    DEFAULT_GH_USERNAME=$(prompt "GitHub username" "$DEFAULT_GH_USERNAME")
    
    echo ""
    show_menu "Select license" "MIT" "Apache-2.0" "GPL-3.0" "BSD-3-Clause" "No License"
    read -r lic_choice
    case "${lic_choice:-1}" in
        1) DEFAULT_LICENSE="MIT" ;;
        2) DEFAULT_LICENSE="Apache-2.0" ;;
        3) DEFAULT_LICENSE="GPL-3.0" ;;
        4) DEFAULT_LICENSE="BSD-3-Clause" ;;
        5) DEFAULT_LICENSE="" ;;
    esac
    
    echo ""
    log_info "Feature Selection:"
    echo ""
    
    if confirm "Add commitlint & conventional commits?" "$FEATURE_COMMITLINT"; then
        FEATURE_COMMITLINT=true
    else
        FEATURE_COMMITLINT=false
    fi
    
    if confirm "Add auto-versioning (standard-version)?" "$FEATURE_STANDARD_VERSION"; then
        FEATURE_STANDARD_VERSION=true
    else
        FEATURE_STANDARD_VERSION=false
    fi
    
    if confirm "Add git hooks (husky)?" "$FEATURE_HUSKY"; then
        FEATURE_HUSKY=true
    else
        FEATURE_HUSKY=false
    fi
    
    if confirm "Add branch protection rules?" "$FEATURE_BRANCH_PROTECTION"; then
        FEATURE_BRANCH_PROTECTION=true
    else
        FEATURE_BRANCH_PROTECTION=false
    fi
    
    if confirm "Add PR template?" "$FEATURE_PR_TEMPLATE"; then
        FEATURE_PR_TEMPLATE=true
    else
        FEATURE_PR_TEMPLATE=false
    fi
    
    if confirm "Add issue templates?" "$FEATURE_ISSUE_TEMPLATES"; then
        FEATURE_ISSUE_TEMPLATES=true
    else
        FEATURE_ISSUE_TEMPLATES=false
    fi
    
    if confirm "Generate .gitignore?" "$FEATURE_GITIGNORE"; then
        FEATURE_GITIGNORE=true
    else
        FEATURE_GITIGNORE=false
    fi
    
    if confirm "Generate README?" "$FEATURE_README"; then
        FEATURE_README=true
    else
        FEATURE_README=false
    fi
    
    if confirm "Add security policy?" "$FEATURE_SECURITY"; then
        FEATURE_SECURITY=true
    else
        FEATURE_SECURITY=false
    fi
    
    if confirm "Enable CI/CD workflows?" "$FEATURE_CI"; then
        FEATURE_CI=true
    else
        FEATURE_CI=false
    fi
    
    echo ""
}

#===============================================================================
# Template Generators
#===============================================================================

generate_gitignore() {
    local lang=$(prompt "Primary language (node, python, go, rust, java, etc.)" "")
    
    cat > .gitignore << EOF
# Dependencies
node_modules/
vendor/
EOF

    case "$lang" in
        node|npm|javascript|typescript)
            cat >> .gitignore << 'EOF'
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnpm-debug.log*
package-lock.json
yarn.lock

# Build outputs
dist/
build/
*.tsbuildinfo
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF
            ;;
        python|py)
            cat >> .gitignore << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
venv/
env/
.venv/
EOF
            ;;
        go)
            cat >> .gitignore << 'EOF'
# Binaries
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test binary
*.test

# Output of the go coverage tool
*.out

# Dependency directories
vendor/

# Go workspace
go.work
EOF
            ;;
        rust|cargo)
            cat >> .gitignore << 'EOF'
# Build
target/
*.rs.bk

# Cargo
Cargo.lock

# IDE
.idea/
.vscode/
EOF
            ;;
    esac
    
    log_success "Generated .gitignore"
}

generate_readme() {
    cat > README.md << EOF
# $DEFAULT_REPO_NAME

$DEFAULT_REPO_DESCRIPTION

## Getting Started

\`\`\`bash
# Clone the repository
git clone https://github.com/$DEFAULT_GH_USERNAME/$DEFAULT_REPO_NAME.git
cd $DEFAULT_REPO_NAME

# Install dependencies
# (add your install commands here)
\`\`\`

## Features

- Feature 1
- Feature 2
- Feature 3

## Contributing

Contributions are welcome! Please read our [contributing guidelines](CONTRIBUTING.md) first.

## License

$( [ -n "$DEFAULT_LICENSE" ] && echo "Licensed under the $DEFAULT_LICENSE license." || echo "No license specified." )

## Author

$DEFAULT_AUTHOR
EOF
    log_success "Generated README.md"
}

generate_license() {
    local year=$(date +%Y)
    
    case "$DEFAULT_LICENSE" in
        MIT)
            cat > LICENSE << EOF
MIT License

Copyright (c) $year $DEFAULT_AUTHOR

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
            ;;
        Apache-2.0)
            cat > LICENSE << EOF
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

Copyright $year $DEFAULT_AUTHOR

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
EOF
            ;;
        GPL-3.0)
            cat > LICENSE << EOF
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007

Copyright (C) $year $DEFAULT_AUTHOR
EOF
            ;;
        BSD-3-Clause)
            cat > LICENSE << EOF
BSD 3-Clause License

Copyright (c) $year $DEFAULT_AUTHOR
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.
EOF
            ;;
    esac
    
    log_success "Generated LICENSE ($DEFAULT_LICENSE)"
}

generate_commitlint_config() {
    cat > commitlint.config.js << 'EOF'
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'chore', 'revert']
    ],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    'header-max-length': [2, 'always', 100],
  },
};
EOF
    log_success "Generated commitlint.config.js"
}

generate_package_json() {
    cat > package.json << EOF
{
  "name": "$DEFAULT_REPO_NAME",
  "version": "1.0.0",
  "description": "$DEFAULT_REPO_DESCRIPTION",
  "scripts": {
    "release": "standard-version",
    "release:minor": "standard-version --release-as minor",
    "release:major": "standard-version --release-as major",
    "release:patch": "standard-version --release-as patch",
    "commitlint": "commitlint --edit",
    "prepare": "if [ -d .git ]; then npx husky install || true; fi"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/$DEFAULT_GH_USERNAME/$DEFAULT_REPO_NAME.git"
  },
  "keywords": [],
  "author": "$DEFAULT_AUTHOR",
  "license": "$DEFAULT_LICENSE",
  "devDependencies": {
    "@commitlint/cli": "^19.0.0",
    "@commitlint/config-conventional": "^19.0.0",
    "husky": "^9.0.0",
    "standard-version": "^9.3.0"
  }
}
EOF
    log_success "Generated package.json"
}

generate_husky_hooks() {
    mkdir -p .husky
    cat > .husky/commit-msg << 'EOF'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"
npx --no -- commitlint --edit ${1}
EOF
    chmod +x .husky/commit-msg
    log_success "Generated husky hooks"
}

generate_pr_template() {
    mkdir -p .github
    cat > .github/pull_request_template.md << 'EOF'
## Description
<!-- Brief description of the changes -->

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
<!-- How has this been tested? -->

## Checklist
- [ ] My code follows the style guidelines
- [ ] I have performed a self-review
- [ ] I have commented my code
- [ ] My changes generate no new warnings
- [ ] I have added tests
EOF
    log_success "Generated PR template"
}

generate_issue_templates() {
    mkdir -p .github/ISSUE_TEMPLATE
    
    cat > .github/ISSUE_TEMPLATE/bug_report.md << 'EOF'
---
name: Bug Report
title: 'fix: '
labels: bug
---

## Description

## Steps to Reproduce

## Expected Behavior

## Actual Behavior
EOF

    cat > .github/ISSUE_TEMPLATE/feature_request.md << 'EOF'
---
name: Feature Request
title: 'feat: '
labels: enhancement
---

## Is your feature related to a problem?

## Desired Solution
EOF

    log_success "Generated issue templates"
}

generate_security_policy() {
    cat > SECURITY.md << 'EOF'
# Security Policy

## Reporting Security Vulnerabilities

Please report security vulnerabilities by email to the maintainers.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Best Practices

- Keep dependencies updated
- Use environment variables for secrets
- Follow the principle of least privilege
EOF
    log_success "Generated SECURITY.md"
}

generate_ci_workflow() {
    mkdir -p .github/workflows
    
    cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test
EOF

    if [ "$FEATURE_COMMITLINT" = true ]; then
        cat >> .github/workflows/ci.yml << 'EOF'

  commitlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - name: Validate commits
        run: npx commitlint --from HEAD~1 --to HEAD
EOF
    fi
    
    log_success "Generated CI workflow"
}

setup_github_repo() {
    if ! command -v gh &>/dev/null; then
        log_warn "GitHub CLI not found. Skipping repo creation."
        return 0
    fi
    
    if gh repo view "$DEFAULT_GH_USERNAME/$DEFAULT_REPO_NAME" &>/dev/null; then
        log_warn "Repository already exists on GitHub"
        return 0
    fi
    
    if confirm "Create GitHub repository?" "y"; then
        gh repo create "$DEFAULT_REPO_NAME" \
            --public \
            --description "$DEFAULT_REPO_DESCRIPTION" \
            --source=. \
            --push
        
        log_success "Created and pushed to GitHub"
    fi
}

setup_branch_protection() {
    if [ "$FEATURE_BRANCH_PROTECTION" != true ]; then
        return 0
    fi
    
    if ! command -v gh &>/dev/null; then
        log_warn "GitHub CLI not found. Skipping branch protection."
        return 0
    fi
    
    local protection_config='{
        "required_status_checks": null,
        "required_pull_request_reviews": {
            "dismiss_stale_reviews": true,
            "require_code_owner_reviews": false,
            "required_approving_review_count": 1
        },
        "enforce_admins": null,
        "allow_force_pushes": false,
        "allow_deletions": false,
        "required_linear_history": true,
        "restrictions": null
    }'
    
    echo "$protection_config" | gh api "repos/$DEFAULT_GH_USERNAME/$DEFAULT_REPO_NAME/branches/main/protection" \
        --input /dev/stdin \
        --method PUT 2>/dev/null || log_warn "Could not set branch protection"
    
    log_success "Configured branch protection"
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo-name)
                DEFAULT_REPO_NAME="$2"
                shift 2
                ;;
            --description)
                DEFAULT_REPO_DESCRIPTION="$2"
                shift 2
                ;;
            --author)
                DEFAULT_AUTHOR="$2"
                shift 2
                ;;
            --gh-username)
                DEFAULT_GH_USERNAME="$2"
                shift 2
                ;;
            --license)
                DEFAULT_LICENSE="$2"
                shift 2
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            --detect)
                AUTO_DETECT=true
                shift
                ;;
            --no-detect)
                AUTO_DETECT=false
                shift
                ;;
            --commitlint) FEATURE_COMMITLINT=true; shift ;;
            --no-commitlint) FEATURE_COMMITLINT=false; shift ;;
            --versioning) FEATURE_STANDARD_VERSION=true; shift ;;
            --no-versioning) FEATURE_STANDARD_VERSION=false; shift ;;
            --husky) FEATURE_HUSKY=true; shift ;;
            --no-husky) FEATURE_HUSKY=false; shift ;;
            --branch-protection) FEATURE_BRANCH_PROTECTION=true; shift ;;
            --no-branch-protection) FEATURE_BRANCH_PROTECTION=false; shift ;;
            --pr-template) FEATURE_PR_TEMPLATE=true; shift ;;
            --no-pr-template) FEATURE_PR_TEMPLATE=false; shift ;;
            --issue-templates) FEATURE_ISSUE_TEMPLATES=true; shift ;;
            --no-issue-templates) FEATURE_ISSUE_TEMPLATES=false; shift ;;
            --gitignore) FEATURE_GITIGNORE=true; shift ;;
            --no-gitignore) FEATURE_GITIGNORE=false; shift ;;
            --readme) FEATURE_README=true; shift ;;
            --no-readme) FEATURE_README=false; shift ;;
            --security) FEATURE_SECURITY=true; shift ;;
            --no-security) FEATURE_SECURITY=false; shift ;;
            --ci) FEATURE_CI=true; shift ;;
            --no-ci) FEATURE_CI=false; shift ;;
            --all)
                FEATURE_COMMITLINT=true
                FEATURE_STANDARD_VERSION=true
                FEATURE_HUSKY=true
                FEATURE_BRANCH_PROTECTION=true
                FEATURE_PR_TEMPLATE=true
                FEATURE_ISSUE_TEMPLATES=true
                FEATURE_GITIGNORE=true
                FEATURE_README=true
                FEATURE_SECURITY=true
                FEATURE_CI=true
                shift
                ;;
            --defaults)
                INTERACTIVE=false
                shift
                ;;
            --help|-h)
                print_usage
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                ;;
        esac
    done
    
    # Auto detect
    if [ "$AUTO_DETECT" = true ]; then
        detect_git_config
    fi
    
    # Interactive mode
    if [ "$INTERACTIVE" = true ]; then
        interactive_setup
    fi
    
    # Validate required fields
    if [ -z "$DEFAULT_REPO_NAME" ]; then
        log_error "Repository name is required"
        exit 1
    fi
    
    if [ -z "$DEFAULT_GH_USERNAME" ]; then
        log_error "GitHub username is required"
        exit 1
    fi
    
    # Print summary
    print_header
    log_info "Setting up: $DEFAULT_REPO_NAME"
    log_info "Author: $DEFAULT_AUTHOR"
    log_info "GitHub: $DEFAULT_GH_USERNAME"
    echo ""
    
    # Generate files
    if [ -n "$DEFAULT_LICENSE" ] && [ ! -f LICENSE ]; then
        generate_license
    fi
    
    if [ "$FEATURE_GITIGNORE" = true ] && [ ! -f .gitignore ]; then
        generate_gitignore
    fi
    
    if [ "$FEATURE_README" = true ] && [ ! -f README.md ]; then
        generate_readme
    fi
    
    if [ "$FEATURE_SECURITY" = true ] && [ ! -f SECURITY.md ]; then
        generate_security_policy
    fi
    
    if [ "$FEATURE_COMMITLINT" = true ] || [ "$FEATURE_STANDARD_VERSION" = true ]; then
        [ ! -f commitlint.config.js ] && generate_commitlint_config
        [ ! -f package.json ] && generate_package_json
    fi
    
    if [ "$FEATURE_HUSKY" = true ] && [ ! -d .husky ]; then
        generate_husky_hooks
    fi
    
    if [ "$FEATURE_PR_TEMPLATE" = true ] && [ ! -f .github/pull_request_template.md ]; then
        generate_pr_template
    fi
    
    if [ "$FEATURE_ISSUE_TEMPLATES" = true ] && [ ! -d .github/ISSUE_TEMPLATE ]; then
        generate_issue_templates
    fi
    
    if [ "$FEATURE_CI" = true ] && [ ! -d .github/workflows ]; then
        generate_ci_workflow
    fi
    
    echo ""
    log_success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated files"
    echo "  2. Commit and push:"
    echo "     git add ."
    echo "     git commit -m 'feat: initial setup'"
    echo "     git push -u origin main"
    echo ""
    
    if [ "$FEATURE_BRANCH_PROTECTION" = true ]; then
        echo "  3. Configure branch protection (requires admin access)"
        echo "     The script can do this with: gh api ..."
    fi
}

main "$@"
