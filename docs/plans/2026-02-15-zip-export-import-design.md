# Zip Export/Import Design

## Purpose

Allow users to export a sequence as a zip file and import a sequence from a zip file, enabling sharing sequences between Stepbook instances.

## Decisions

- **Server-side** zip creation and parsing (server has direct access to images on disk)
- **Always create new** on import (fresh UUIDs, no conflict resolution needed)
- **UI on home page** — export button on each sequence card, import button near "Create"

## Zip Format

```
sequence-export.zip
├── manifest.json
└── images/
    ├── 0.png
    ├── 1.jpg
    └── ...
```

**manifest.json:**
```json
{
  "version": 1,
  "sequence": {
    "title": "My Tutorial",
    "description": "How to do X"
  },
  "steps": [
    {
      "order_index": 0,
      "image_filename": "0.png",
      "annotations": { "lines": [], "labels": [] },
      "notes": "Step 1 instructions"
    }
  ]
}
```

No original IDs — irrelevant for sharing. `version` field future-proofs the format.

## API Endpoints

### `GET /api/sequences/:id/export`

- Fetches sequence + steps from DB
- Reads step images from disk
- Builds zip in memory with `archiver`
- Returns zip as `application/zip` with `Content-Disposition: attachment`

### `POST /api/sequences/import`

- Accepts zip upload via multer (single file)
- Extracts and validates `manifest.json`
- Creates new sequence with fresh UUID
- For each step: generates fresh step UUID, copies image to `data/images/{seqId}/{stepId}.ext`, inserts DB row
- Returns the newly created sequence object

## UI Changes

### SequenceList.vue (home page)

- Add export button (download icon) on each sequence card
- Add "Import Sequence" button next to "New Sequence" button
- Import button opens file picker for `.zip` files
- Show loading state during import, then refresh sequence list

### api.js (client)

- `exportSequence(id)` — triggers download of zip file
- `importSequence(file)` — uploads zip file, returns new sequence

## Dependencies

- `archiver` — create zip files server-side
- `adm-zip` — read/extract zip files on import

## Server Route Organization

New file: `server/routes/transfer.js` for export/import endpoints, keeping them separate from existing CRUD routes.
