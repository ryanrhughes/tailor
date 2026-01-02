#!/bin/bash
#
# install-bmad-opencode.sh
# 
# Installs BMAD Method v6 for OpenCode
# Adapts the Claude Code BMAD skills to OpenCode's directory structure
#
# Usage:
#   chmod +x install-bmad-opencode.sh
#   ./install-bmad-opencode.sh
#
# Options:
#   --force     Overwrite existing installation
#   --uninstall Remove BMAD from OpenCode
#   --dry-run   Show what would be done without making changes
#

# Don't use set -e as it causes issues with arithmetic expansion
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/aj-geddes/claude-code-bmad-skills.git"
REPO_BRANCH="main"
TMP_DIR="/tmp/bmad-opencode-install-$$"

# OpenCode paths
OPENCODE_SKILL_DIR="$HOME/.opencode/skill"
OPENCODE_COMMAND_DIR="$HOME/.config/opencode/command"
OPENCODE_CONFIG_DIR="$HOME/.config/opencode/bmad"

# Parse arguments
FORCE=false
UNINSTALL=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force      Overwrite existing installation"
            echo "  --uninstall  Remove BMAD from OpenCode"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    if [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v git &> /dev/null; then
        log_error "git is required but not installed"
        exit 1
    fi
    
    log_success "Prerequisites satisfied"
}

# Uninstall BMAD
uninstall_bmad() {
    log_info "Uninstalling BMAD from OpenCode..."
    
    # List of BMAD skills to remove
    local skills=(
        "bmad-master"
        "analyst"
        "pm"
        "architect"
        "scrum-master"
        "developer"
        "ux-designer"
        "builder"
        "creative-intelligence"
    )
    
    # List of BMAD commands to remove
    local commands=(
        "workflow-init"
        "workflow-status"
        "product-brief"
        "prd"
        "tech-spec"
        "architecture"
        "solutioning-gate-check"
        "sprint-planning"
        "create-story"
        "dev-story"
        "create-agent"
        "create-workflow"
        "brainstorm"
        "research"
        "create-ux-design"
    )
    
    # Remove skills
    for skill in "${skills[@]}"; do
        local skill_path="$OPENCODE_SKILL_DIR/$skill"
        if [ -d "$skill_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY-RUN] Would remove: $skill_path"
            else
                rm -rf "$skill_path"
                log_success "Removed skill: $skill"
            fi
        fi
    done
    
    # Remove commands
    for cmd in "${commands[@]}"; do
        local cmd_path="$OPENCODE_COMMAND_DIR/$cmd.md"
        if [ -f "$cmd_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY-RUN] Would remove: $cmd_path"
            else
                rm -f "$cmd_path"
                log_success "Removed command: $cmd"
            fi
        fi
    done
    
    # Remove config
    if [ -d "$OPENCODE_CONFIG_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would remove: $OPENCODE_CONFIG_DIR"
        else
            rm -rf "$OPENCODE_CONFIG_DIR"
            log_success "Removed BMAD config directory"
        fi
    fi
    
    log_success "BMAD uninstalled from OpenCode"
}

# Clone repository
clone_repo() {
    log_info "Cloning BMAD repository..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would clone $REPO_URL to $TMP_DIR"
        return
    fi
    
    mkdir -p "$TMP_DIR"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR" 2>/dev/null
    
    if [ ! -d "$TMP_DIR/bmad-v6" ]; then
        log_error "Repository structure unexpected - bmad-v6 directory not found"
        exit 1
    fi
    
    log_success "Repository cloned"
}

# Create directories
create_directories() {
    log_info "Creating OpenCode directories..."
    
    local dirs=(
        "$OPENCODE_SKILL_DIR"
        "$OPENCODE_COMMAND_DIR"
        "$OPENCODE_CONFIG_DIR"
        "$OPENCODE_CONFIG_DIR/templates"
    )
    
    for dir in "${dirs[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would create: $dir"
        else
            mkdir -p "$dir"
        fi
    done
    
    log_success "Directories created"
}

# Install skills
install_skills() {
    log_info "Installing BMAD skills..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would install skills from $TMP_DIR/bmad-v6/skills/"
        return
    fi
    
    local skill_count=0
    
    # Walk through the skills directory structure
    # Structure: bmad-v6/skills/{module}/{agent}/SKILL.md
    for module_dir in "$TMP_DIR/bmad-v6/skills/"*/; do
        if [ -d "$module_dir" ]; then
            for agent_dir in "$module_dir"*/; do
                if [ -d "$agent_dir" ] && [ -f "$agent_dir/SKILL.md" ]; then
                    local skill_name=$(basename "$agent_dir")
                    local dest_dir="$OPENCODE_SKILL_DIR/$skill_name"
                    
                    # Check if already exists
                    if [ -d "$dest_dir" ] && [ "$FORCE" = false ]; then
                        log_warn "Skill '$skill_name' already exists (use --force to overwrite)"
                        continue
                    fi
                    
                    mkdir -p "$dest_dir"
                    cp "$agent_dir/SKILL.md" "$dest_dir/"
                    
                    # Copy any additional files in the skill directory
                    for file in "$agent_dir"/*; do
                        if [ -f "$file" ] && [ "$(basename "$file")" != "SKILL.md" ]; then
                            cp "$file" "$dest_dir/"
                        fi
                    done
                    
                    log_success "Installed skill: $skill_name"
                    skill_count=$((skill_count + 1))
                fi
            done
        fi
    done
    
    log_success "Installed $skill_count skills"
}

# Convert BMAD command to OpenCode format
convert_command() {
    local src_file="$1"
    local cmd_name="$2"
    local dest_file="$3"
    
    # Use static descriptions to avoid YAML parsing issues
    # (BMAD commands may contain {{templates}} or special chars that break YAML)
    local description=""
    
    case "$cmd_name" in
        "workflow-init") description="Initialize BMAD workflow in project" ;;
        "workflow-status") description="Check BMAD workflow status" ;;
        "product-brief") description="Create product brief document" ;;
        "prd") description="Create Product Requirements Document" ;;
        "tech-spec") description="Create lightweight tech specification" ;;
        "architecture") description="Create system architecture document" ;;
        "solutioning-gate-check") description="Validate architecture quality" ;;
        "sprint-planning") description="Plan sprint iterations" ;;
        "create-story") description="Create user story" ;;
        "dev-story") description="Implement user story" ;;
        "create-agent") description="Create custom BMAD agent" ;;
        "create-workflow") description="Create custom workflow" ;;
        "brainstorm") description="Structured brainstorming session" ;;
        "research") description="Conduct research analysis" ;;
        "create-ux-design") description="Create UX design document" ;;
        *) description="BMAD workflow command" ;;
    esac
    
    # Create OpenCode-compatible command with frontmatter
    # Use quoted description to be safe with special characters
    {
        echo "---"
        echo "description: \"$description\""
        echo "---"
        echo ""
        cat "$src_file"
    } > "$dest_file"
}

# Install commands
install_commands() {
    log_info "Installing BMAD commands..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would install commands from $TMP_DIR/bmad-v6/commands/"
        return
    fi
    
    local cmd_count=0
    
    for cmd_file in "$TMP_DIR/bmad-v6/commands/"*.md; do
        if [ -f "$cmd_file" ]; then
            local cmd_name=$(basename "$cmd_file" .md)
            local dest_file="$OPENCODE_COMMAND_DIR/$cmd_name.md"
            
            # Check if already exists
            if [ -f "$dest_file" ] && [ "$FORCE" = false ]; then
                log_warn "Command '$cmd_name' already exists (use --force to overwrite)"
                continue
            fi
            
            convert_command "$cmd_file" "$cmd_name" "$dest_file"
            log_success "Installed command: /$cmd_name"
            cmd_count=$((cmd_count + 1))
        fi
    done
    
    log_success "Installed $cmd_count commands"
}

# Install config and helpers
install_config() {
    log_info "Installing BMAD config and helpers..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would install config to $OPENCODE_CONFIG_DIR"
        return
    fi
    
    # Copy helpers
    if [ -f "$TMP_DIR/bmad-v6/utils/helpers.md" ]; then
        cp "$TMP_DIR/bmad-v6/utils/helpers.md" "$OPENCODE_CONFIG_DIR/"
        log_success "Installed helpers.md"
    fi
    
    # Copy templates
    if [ -d "$TMP_DIR/bmad-v6/templates" ]; then
        cp -r "$TMP_DIR/bmad-v6/templates/"* "$OPENCODE_CONFIG_DIR/templates/" 2>/dev/null || true
        log_success "Installed templates"
    fi
    
    # Create config.yaml for OpenCode
    cat > "$OPENCODE_CONFIG_DIR/config.yaml" << 'EOF'
# BMAD Method v6 Configuration for OpenCode
# 
# This file contains global settings for BMAD workflows

bmad:
  version: "6.0"
  client: "opencode"
  
  # Default output directory for BMAD documents
  output_folder: "bmad-outputs"
  
  # Language for generated documents
  language: "en"
  
  # Paths (relative to ~/.config/opencode/bmad/)
  paths:
    helpers: "helpers.md"
    templates: "templates"

# Project level defaults
# Level 0: 1 story (minimal)
# Level 1: 1-10 stories (light)
# Level 2: 5-15 stories (standard)
# Level 3: 12-40 stories (comprehensive)
# Level 4: 40+ stories (enterprise)
defaults:
  project_level: 2
EOF
    
    log_success "Installed config.yaml"
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  BMAD Method v6 installed for OpenCode${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Installed to:"
    echo "  Skills:   $OPENCODE_SKILL_DIR"
    echo "  Commands: $OPENCODE_COMMAND_DIR"
    echo "  Config:   $OPENCODE_CONFIG_DIR"
    echo ""
    echo "9 Specialized Skills:"
    echo "  - bmad-master (orchestrator)"
    echo "  - analyst (business analysis)"
    echo "  - pm (product manager)"
    echo "  - architect (system design)"
    echo "  - scrum-master (sprint planning)"
    echo "  - developer (implementation)"
    echo "  - ux-designer (user experience)"
    echo "  - builder (custom agents)"
    echo "  - creative-intelligence (brainstorming)"
    echo ""
    echo "15 Workflow Commands:"
    echo "  /workflow-init    - Initialize BMAD in project"
    echo "  /workflow-status  - Check project status"
    echo "  /product-brief    - Phase 1: Product discovery"
    echo "  /prd              - Phase 2: Detailed requirements"
    echo "  /tech-spec        - Phase 2: Lightweight requirements"
    echo "  /architecture     - Phase 3: System design"
    echo "  /solutioning-gate-check - Validate design"
    echo "  /sprint-planning  - Phase 4: Plan sprint"
    echo "  /create-story     - Create user story"
    echo "  /dev-story        - Implement story"
    echo "  /create-agent     - Create custom agent"
    echo "  /create-workflow  - Create custom workflow"
    echo "  /brainstorm       - Structured brainstorming"
    echo "  /research         - Market/tech research"
    echo "  /create-ux-design - UX design"
    echo ""
    echo "Next Steps:"
    echo "  1. Restart OpenCode (skills load on startup)"
    echo "  2. Open your project directory"
    echo "  3. Run: /workflow-init"
    echo "  4. Run: /workflow-status"
    echo ""
}

# Main
main() {
    echo ""
    echo -e "${BLUE}BMAD Method v6 Installer for OpenCode${NC}"
    echo ""
    
    if [ "$UNINSTALL" = true ]; then
        uninstall_bmad
        exit 0
    fi
    
    check_prerequisites
    clone_repo
    create_directories
    install_skills
    install_commands
    install_config
    
    if [ "$DRY_RUN" = false ]; then
        print_summary
    else
        echo ""
        log_info "[DRY-RUN] No changes were made"
        echo ""
    fi
}

main "$@"
