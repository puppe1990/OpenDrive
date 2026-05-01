# Trash Permanent Delete Visual Feedback Design

Date: 2026-05-01
Project: OpenDrive
Area: `OpenDriveWeb.TrashLive.Index`

## Goal

Improve the visual feedback when the user permanently empties the trash so the UI clearly communicates that a destructive operation is in progress.

The current flow only shows a confirmation modal and, after the deletion completes, closes the modal and displays a flash message. This makes the action feel abrupt and provides little confidence that the system is actually processing the deletion.

## Desired User Experience

After the user confirms `Empty trash`, the confirmation modal should immediately transition into a locked processing state.

The processing state should:

- show that permanent deletion is actively running
- block dismissal and cancellation while the operation is in flight
- darken the page more aggressively than the current modal state
- use a more expressive high-risk visual language: dark slate base, rose/amber warning glow, and deliberate motion
- keep the context of impact visible so the user still understands what is being deleted

When the deletion finishes:

- the modal closes
- the trash list reloads
- the existing success flash remains the completion confirmation

If the deletion fails:

- the processing state ends
- the modal closes
- the existing error flash remains the failure confirmation

## Recommended Approach

Use a two-phase LiveView flow inside the existing trash modal.

Phase 1 is the current confirmation state.
Phase 2 is a new processing state rendered from the same modal container.

This is the best tradeoff because it keeps the destructive action anchored in the current interaction model, avoids extra client-side orchestration, and ensures the processing UI can render before the deletion work begins.

## State Model

Add a new assign:

- `:emptying_trash` - boolean

Existing assign kept:

- `:confirm_empty_trash` - boolean

Expected combinations:

- `confirm_empty_trash: false`, `emptying_trash: false`
  Normal page, no modal.
- `confirm_empty_trash: true`, `emptying_trash: false`
  Confirmation modal.
- `confirm_empty_trash: true`, `emptying_trash: true`
  Processing modal.

`emptying_trash: true` should only exist while the modal is open. It should always be reset to `false` after success or failure.

## Event Flow

### Open modal

`open_empty_trash_modal`

- sets `confirm_empty_trash: true`
- sets `emptying_trash: false`

### Cancel modal

`cancel_empty_trash`

- only works when `emptying_trash` is `false`
- sets both flags to `false`

If `emptying_trash` is `true`, cancel should be ignored.

### Start deletion

`empty_trash`

This event must not call `Drive.empty_trash/1` directly.

Instead it should:

1. set `emptying_trash: true`
2. trigger an internal async step using `send(self(), :empty_trash)`

Reason:

If the deletion runs inside the same event handler before the assign is rendered, the user never sees the processing state. Deferring the actual delete to `handle_info/2` allows LiveView to paint the loading UI first.

### Execute deletion

`handle_info(:empty_trash, socket)`

- calls `Drive.empty_trash/1`
- on success:
  - sets `confirm_empty_trash: false`
  - sets `emptying_trash: false`
  - reloads trash data
  - shows existing success flash
- on failure:
  - sets `confirm_empty_trash: false`
  - sets `emptying_trash: false`
  - shows existing error flash

## UI Design Direction

Tone:

- tense / dangerous
- premium / deliberate motion

Signature move:

- the confirmation modal transforms into an “incineration in progress” state using a darkened shell, heated edge glow, and a moving progress band rather than a generic spinner

## Modal Processing State

### Visual structure

Reuse the existing modal shell, but switch its contents and visual treatment when `@emptying_trash` is true.

Processing modal should include:

- darker overlay with stronger blur
- modal panel shifted from bright white to deep slate with subtle rose/amber gradient energy
- animated central icon or badge based on trash/destructive action
- status eyebrow such as `Permanent removal in progress`
- heading such as `Removing items from trash`
- short support copy reinforcing irreversibility
- compact impact summary preserving `%{files}` and `%{folders}`
- indeterminate animated progress bar
- disabled action pill instead of clickable confirm button

### Interaction rules

While processing:

- clicking the backdrop does nothing
- the close hit-area should not render
- `Cancel` should not render
- the confirm action should render as disabled, non-interactive status
- the destructive modal should remain centered and stable without layout jumps

### Accessibility

- keep semantic button usage where interactive
- disabled action should still have visible text state
- motion should be subtle and repeatable, not flashing
- respect reduced-motion preferences by disabling sweeping/transform animations and keeping only static emphasis

## Copy Direction

Confirmation state can keep its current structure.

Processing state copy should be short and explicit. The implementation should use the following copy:

- eyebrow: `Permanent removal in progress`
- title: `Removing items from trash`
- body: `Files and folders are being deleted from the trash and removed from storage. This cannot be undone.`
- status pill: `Deleting permanently...`

## Animation and Motion

Use CSS-only motion inside the LiveView template.

Preferred motion primitives:

- pulse/glow on the destructive icon container
- slow shimmer or sweep across the progress track
- gentle breathing shadow on the modal container

Do not:

- spin a default loader without context
- add abrupt bouncing movement
- use excessive motion that trivializes the destructive action

## Testing Plan

Update `test/open_drive_web/live/trash_live/index_test.exs` to cover:

- processing-state markup appears after triggering `empty_trash`
- processing copy and disabled-state affordances are rendered
- cancel affordances are hidden or inactive while processing

If the LiveView test cannot reliably observe the intermediate state in a simple way, add a focused render-level assertion strategy around the assign-driven state.

No domain changes are expected in `Drive.empty_trash/1`.

## Scope Boundaries

Included:

- Trash LiveView state handling
- Trash modal visual processing state
- Loading/locking behavior during permanent deletion
- Test coverage for the new UI state

Excluded:

- changing the deletion semantics in `Drive`
- adding background jobs
- adding granular progress percentages
- redesigning restore interactions
- changing success/error flash architecture

## Risks and Mitigations

### Risk: intermediate loading state never appears

Mitigation:

- perform deletion in `handle_info/2` after setting `emptying_trash: true`

### Risk: users can dismiss the modal mid-delete

Mitigation:

- remove clickable backdrop close and cancel affordances while processing

### Risk: motion feels noisy or cheap

Mitigation:

- keep animation limited to one icon emphasis and one indeterminate progress treatment

## Implementation Summary

The implementation should keep the current Trash page architecture intact and only extend the modal interaction model.

The key behavioral change is introducing a real processing phase that renders before `Drive.empty_trash/1` executes. The key visual change is turning the destructive modal into a locked, premium, high-risk progress state instead of relying on a post-action flash alone.
