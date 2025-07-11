# Get notes info for specific note IDs (replace with actual note IDs from findNotes)
# You'll need to run the 'findNotes' query first and use some of the returned IDs here.
POST http://localhost:8765
Content-Type: application/json
{
    "action": "notesInfo",
    "version": 6,
    "params": {
        "notes": [1688234567890, 1688234567891] # Replace with actual note IDs
    }
}

HTTP 200
[Asserts]
jsonpath "$.result" isCollection
