# iOS App Feature Roadmap

## Overview

Four new features for the Stepbook iOS app, prioritized by complexity and impact.

## 1. Search (Up Next)

**Goal:** Full-text search across sequence titles, descriptions, and step notes.

**Approach:** In-memory search. Load all text from SQLite, normalize, and run search
in-process. Avoids DB migration and backwards-compatibility issues. Acceptable
given expected database sizes (dozens to hundreds of sequences).

**UI:** SwiftUI `.searchable()` modifier on BookListView and SequenceListView.
Results grouped by book > sequence > step, tapping navigates to the match.

## 2. Tags & Categories

**Goal:** Label sequences with tags and filter/browse by tag.

**Approach:** New `tags` and `sequence_tags` tables per BookDatabase (many-to-many
join). Tag picker UI on sequence creation/edit, filter chips on SequenceListView.

## 3. Speech-to-Text Notes

**Goal:** Dictate step notes via voice instead of typing.

**Approach:** Apple's `SFSpeechRecognizer` for on-device transcription (iOS 17+).
Microphone button next to the notes text field in the editor. Tap to record,
release to stop, transcription appends to notes. User edits before saving.

Requires microphone permission (`NSSpeechRecognitionUsageDescription`). No network
dependency.

## 4. Video Steps

**Goal:** Allow short video clips as steps alongside photos.

**Approach:** Extend `Step` model with `mediaType` field (`.photo` or `.video`).
Store video files alongside images. AVPlayer inline in view mode (auto-play muted,
tap to unmute). Video capture and library picker in edit mode. ZIP export includes
video files.

Largest feature — impacts data model, viewer, editor, import/export, and storage.
Needs video size limits and compression strategy.
