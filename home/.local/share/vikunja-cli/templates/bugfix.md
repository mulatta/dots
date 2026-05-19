---
name: bugfix
description: Fix reproducible broken behavior.
defaults:
  priority: 4
  labels:
    - type:bugfix
    - state:next
schema:
  $schema: https://json-schema.org/draft/2020-12/schema
  type: object
  title: bugfix context
  description: Fix reproducible broken behavior.
  additionalProperties: false
  required:
    - summary
    - checklist
    - proof
  properties:
    summary:
      type: string
      minLength: 1
      description:
        One-line task outcome. Write the value in the user's language.
        Do not include due date, priority, labels, project, bucket, reminders, or
        relations.
    checklist:
      type: array
      items:
        type: string
      minItems: 3
      maxItems: 5
      description: Milestones like reproduce, add regression test, fix, verify.
    notes:
      type: array
      items:
        type: string
      maxItems: 6
      description:
        Short execution notes, constraints, extracted facts, or unresolved
        questions. One line per item. Write notes in the user's language.
    proof:
      type: array
      items:
        type: string
      maxItems: 3
      description: Passing test, build, or log command.
      minItems: 1
    sources:
      type: array
      items:
        $ref: "#/$defs/Source"
      maxItems: 5
      description:
        Clickable or directly openable sources only. Do not include bare
        email Message-Id values. Extract non-openable email facts into notes instead.
  $defs:
    SourceKind:
      type: string
      enum:
        - url
        - webmail
        - file
        - attached
        - notmuch
        - maildir
        - issue
        - pr
        - ci
        - docs
        - other
    Source:
      type: object
      additionalProperties: false
      required:
        - kind
        - locator
      properties:
        kind:
          $ref: "#/$defs/SourceKind"
        locator:
          type: string
          minLength: 1
          description:
            Openable URL, webmail URL, file path, attachment name, or searchable
            local locator. No bare Message-Id.
        title:
          type: string
          description: Short human label in the user's language.
  x-note_hints:
    - reproduction
    - expected behavior
    - actual behavior
    - suspected area
    - verification command
  x-language_policy:
    fixed_language: English
    fixed_items:
      - schema keys
      - Markdown headings
      - source kinds
      - template names
      - fixed template labels
    content_language:
      Use the user's language for human-facing values. If the user
      writes Korean, write summary, checklist, notes, proof, and source titles in
      Korean.
  x-source_policy:
    - Use webmail URLs for email only when they open a specific message or thread.
    - Do not put bare Message-Id values in sources.
    - Use notmuch or maildir only when the locator is actually searchable/openable in
      the user's environment.
    - Attach .eml only when preserving the original message is necessary.
attachment_expectations:
  - Passing test, build, or log command.
---

# bugfix

Fix reproducible broken behavior.

## Context fields

Schema, source kinds, and template-specific constraints live in YAML frontmatter.
