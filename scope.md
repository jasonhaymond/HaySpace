# HaySpace 1.0 Project Scope
Version: 1.0
Status: Approved for Development
Author: Jason Haymond
Project Name: HaySpace
Last Updated: 2026-10-28

---

# Executive Summary

HaySpace is a portable Windows workspace automation platform designed to capture, manage, restore, and migrate complete desktop workspaces across single and multi-monitor environments.

The primary goal is to allow users to recreate an entire working environment with a single action, including:

- Running applications
- Window positions
- Window sizes
- Window states
- Display mappings
- Browser sessions and URLs
- Explorer windows
- Workspace shortcuts
- Hotkey activation

HaySpace must support highly dynamic display environments where monitors may change between sessions, computers, docks, and locations.

The system shall operate as both:

- A portable PowerShell application
- A packaged Windows application

Version 1.0 is focused on single-user operation with future expansion paths for multi-user sharing and enterprise deployment.

---

# Project Vision

## Problem Statement

Users frequently work across multiple monitors and repeatedly rebuild the same workspace every day.

Common examples include:

- Outlook on one monitor
- Teams on another
- ServiceNow in a browser
- PowerShell windows
- Remote Desktop sessions
- Explorer folders
- Administrative tools

Reconstructing these layouts wastes time and reduces productivity.

HaySpace solves this problem by allowing complete workspace capture and restoration.

---

# Core Design Principles

## Simple

Users should not need to manually enter coordinates.

---

## Portable

Profiles should move between computers.

---

## Monitor-Aware

Profiles should survive monitor replacements.

---

## Flexible

Support any application with a standard Windows window.

---

## Visual

Workspace layouts should be viewable and editable visually.

---

## Recoverable

Everything must be exportable and restorable.

---

# Functional Requirements

# Workspace Profiles

A Workspace Profile represents a complete working environment.

Example:

HelpDesk Profile

- Outlook
- Teams
- Edge
- PowerShell
- ServiceNow
- Dell Support
- Lab Monitoring

Stored information includes:

- Applications
- Window locations
- Window dimensions
- Display assignments
- Browser information
- Window states

---

# Profile Types

## Quick Layout

Stores:

- Window position
- Window size
- Display assignment

Does not launch applications.

---

## Workspace Layout

Stores:

- Applications
- Window placement
- Display assignments

Can launch applications.

---

## Full Workspace

Stores:

- Applications
- Window information
- Browser information
- Explorer folders
- Launch order
- Workspace metadata

---

# Display Management

## Display Discovery

HaySpace shall detect:

- Display Name
- Manufacturer
- Model
- Serial Number
- Resolution
- Scaling
- Physical Position

Example:

Left
Center
Right
Laptop

---

## Friendly Naming

Users shall be able to assign custom names.

Example:

- Ticket Screen
- Lab Monitor
- Documentation Screen
- Center Screen

These names are used throughout the application.

---

## Display Remapping

When displays change:

HaySpace shall:

1. Detect mismatch
2. Identify missing displays
3. Prompt for replacement mapping
4. Save remapping options

Example:

Profile expects:

Ticket Screen

Detected:

Dell P2725H

User may map the new display.

---

# Window Management

## Capture

HaySpace shall capture:

- Window Title
- Process Name
- Process Path
- Monitor
- Position
- Size
- State

Supported States:

- Normal
- Maximized
- Minimized

---

## Restore

HaySpace shall:

- Find existing windows
- Launch missing processes
- Restore position
- Restore size
- Restore state

---

## Window Matching

Primary Match:

- Process Name

Secondary Match:

- Window Title

Fallback Match:

- Executable Path

---

# Application Management

## Existing Applications

If application is running:

Move existing window.

---

## Missing Applications

If configured:

Launch application.

---

## Launch Monitoring

After launching:

Wait for window creation.

Then:

- Position
- Resize
- Move

---

# Browser Management

Supported Browsers:

- Microsoft Edge
- Google Chrome
- Mozilla Firefox

---

# Browser Modes

## Ignore

No browser restoration.

---

## URL Mode

Open configured URLs.

---

## Session Mode

Attempt session restoration.

---

## Hybrid Mode

Use existing windows.

Open missing URLs if necessary.

Recommended Default.

---

# Browser Capture

Capture:

- Browser Process
- Window Position
- Active URL (where possible)
- Tab Information (future support)

---

# Explorer Window Support

Capture:

- Folder Path
- Position
- Monitor

Restore:

- Reopen folders
- Restore placement

---

# Remote Desktop Support

Version 1.0:

Capture:

- mstsc windows

Restore:

- Reopen RDP files if configured

Future versions may support session awareness.

---

# Workspace Capture Engine

## Manual Capture

User arranges workspace.

User selects:

Capture Workspace

HaySpace stores profile.

---

## Selective Capture

User may exclude:

- Browser windows
- Explorer windows
- Specific applications

---

# Visual Workspace Designer

## Overview

Visual drag-and-drop monitor canvas.

Displays presented in their actual layout.

Example:

Laptop
Left
Center
Right

---

# Designer Features

- Drag applications
- Resize windows
- Change monitor assignment
- Save profile
- Clone profile

---

# Profile Activation Methods

## GUI

Select profile.

Click Load.

---

## Desktop Shortcut

Generated automatically.

Example:

HelpDesk.lnk

Launches profile.

---

## System Tray

Available Profiles menu.

---

## Hotkeys

Examples:

CTRL+ALT+1

CTRL+ALT+2

CTRL+ALT+3

User configurable.

---

# Shortcuts

Generated per profile.

Stored under:

/Shortcuts

Functions:

- Create
- Delete
- Refresh

---

# Profile Management

## Create

New profile.

---

## Edit

Modify existing profile.

---

## Clone

Duplicate profile.

---

## Delete

Remove profile.

---

## Export

Export profile.

---

## Import

Import profile.

---

# Backup System

## Full Backup

Includes:

- Profiles
- Settings
- Hotkeys
- Display Mappings
- Shortcuts

Output:

HaySpaceBackup.zip

---

# Restore

Import backup archive.

Restore all settings.

---

# Migration Wizard

## New Computer

Detect environment changes.

Guide user through:

- Display mapping
- Path updates
- Profile verification

---

## New Displays

Allow replacing old displays with new displays.

Store persistent mapping.

---

# User Interface Requirements

# Main Dashboard

Sections:

- Profiles
- Actions
- Monitoring
- Settings

Buttons:

- Capture
- Load
- Edit
- Clone
- Delete
- Backup
- Restore

---

# Display Manager Window

Features:

- Monitor detection
- Friendly names
- Display testing
- Mapping editor

---

# Profile Editor

Sections:

- Applications
- Windows
- URLs
- Browser Settings
- Launch Settings
- Hotkeys

---

# Visual Designer

Canvas representation of monitors.

Supports:

- Drag
- Drop
- Resize
- Snap

---

# Tray Application

Features:

- Load Profile
- Capture Workspace
- Settings
- Exit

---

# Architecture

# Application Structure

HaySpace

/Profiles
/Settings
/Monitors
/Backups
/Logs
/Docs
/Icons
/Shortcuts
/Modules
/UI
/Installer

---

# Core Modules

## DisplayManager

Responsibilities:

- Enumerate displays
- Friendly naming
- Mapping

---

## WindowManager

Responsibilities:

- Enumerate windows
- Move windows
- Resize windows

---

## WorkspaceCapture

Responsibilities:

- Capture environment
- Create profile

---

## WorkspaceRestore

Responsibilities:

- Rebuild profile

---

## BrowserManager

Responsibilities:

- Browser integration

---

## ProfileManager

Responsibilities:

- CRUD operations

---

## ShortcutManager

Responsibilities:

- Shortcut generation

---

## BackupManager

Responsibilities:

- Export
- Import

---

## MigrationManager

Responsibilities:

- Display remapping
- Computer migration

---

## LoggingManager

Responsibilities:

- Logging
- Diagnostics

---

# Storage Format

## Profile Format

JSON

Schema Version:

1.0

---

# Example Profile Structure

{
    "ProfileName": "HelpDesk",
    "Version": "1.0",
    "BrowserMode": "Hybrid",
    "Applications": [],
    "Windows": [],
    "Urls": [],
    "ExplorerFolders": [],
    "Displays": []
}

---

# Logging

Log Levels:

- Information
- Warning
- Error
- Debug

Log Location:

/Logs

Rotation:

30 days

---

# Security Requirements

No cloud storage required.

No telemetry.

No external data transmission.

All data remains local.

User-controlled exports only.

---

# Performance Targets

Capture:

< 5 seconds

Restore:

< 30 seconds typical workspace

GUI Launch:

< 3 seconds

Profile Load:

< 2 seconds plus application launch times

---

# Documentation Requirements

The project must include:

README.md

Overview and installation.

---

UserGuide.md

Daily operation.

---

ProfileSchema.md

JSON schema documentation.

---

BackupRestore.md

Backup and migration.

---

DisplayMapping.md

Monitor management.

---

DeveloperGuide.md

Architecture and development.

---

Roadmap.md

Future planning.

---

ChangeLog.md

Version history.

---

# HaySpace 1.0 Deliverables

✅ Workspace Capture Engine

✅ Workspace Restore Engine

✅ Display Discovery

✅ Display Remapping

✅ Friendly Monitor Naming

✅ Browser URL Support

✅ Browser Session Support

✅ Explorer Window Support

✅ Visual Designer

✅ WPF GUI

✅ Tray Application

✅ Desktop Shortcuts

✅ Hotkeys

✅ Profile Management

✅ Backup System

✅ Restore System

✅ Migration Wizard

✅ JSON Profile Storage

✅ Full Documentation

✅ Portable Operation

---

# Deferred to HaySpace 2.0

- Automatic profile switching
- Virtual Desktop support
- Cloud synchronization
- Multi-user profiles
- Shared profile repository
- Teams integration
- PowerShell tab restoration
- Plugin framework
- Update service
- AI workspace recommendations
- Enterprise deployment tooling

---

# Success Criteria

HaySpace 1.0 is considered complete when a user can:

1. Arrange a workspace manually.
2. Capture the workspace into a profile.
3. Restore the workspace from a profile.
4. Migrate the profile to another computer.
5. Remap displays.
6. Launch profiles from shortcuts, hotkeys, tray icon, or GUI.
7. Backup and restore all HaySpace data.
8. Manage all functionality through an intuitive graphical interface.