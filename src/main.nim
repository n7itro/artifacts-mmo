from os import sleep
from strformat import fmt
import json, httpclient

const 
    token = ""
    user = ""
    site = "https://api.artifactsmmo.com"
    data = "character.json"

let client = newHttpClient(headers = newHttpHeaders(
    {"Accept": "application/json",
    "Content-Type": "application/json",
    "Authorization": "Bearer " & token})) 

func success(r: Response): bool =
    r.status == "200 OK"

proc action(endpoint: string, payload: JsonNode = %*""): Response =
    result = client.request(
        fmt"{site}/my/{user}/action/{endpoint}", 
        HttpPost, 
        $payload
    )

    if result.success:
        let body = parseJson result.body
        writeFile data, $body["data"]["character"]

proc attack: Response = action "fight"

proc move(x, y: uint): Response =
    let position = %* {
        "x": x,
        "y": y
    }

    action "move", position

proc cooldown: int =
    let data = parseJson readFile data
    data["cooldown"].num

proc main =
    while attack().success:
        sleep cooldown()
    
    client.close()

when isMainModule:
    main()
