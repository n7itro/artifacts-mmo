{.push discardable.}

from os import sleep
from strformat import fmt
import json, httpclient

const 
    token = ""
    user = ""
    site = "https://api.artifactsmmo.com"

let client = newHttpClient(headers = newHttpHeaders(
    {"Accept": "application/json",
    "Content-Type": "application/json",
    "Authorization": "Bearer " & token})) 

proc cooldown: int =
    let data = readFile("character.json").parseJson
    data["cooldown"].num * 1000

proc getJson(endpoint: string): JsonNode =
    client.request(
        fmt"{site}/{endpoint}", 
        HttpGet
    ).body.parseJson["data"]

proc action(endpoint: string, payload = %* ""): JsonNode =
    result = client.request(
        fmt"{site}/my/{user}/action/{endpoint}", 
        HttpPost, 
        $payload
    ).body.parseJson

    if result.contains("error"):
        # Server lagging
        if result["error"]["code"].num == 486:
            sleep 5_000
            result = action(endpoint, payload)

    # Update the current character details
    else:
        let charData = result["data"]["character"]
        writeFile "character.json", $pretty charData
    
    sleep cooldown()

proc hasDrop(dropType, item: string): string =
    getJson(fmt"{dropType}/?drop={item}")[0]["code"].str

# Harvest resources on current map
proc gather(dropType: string): JsonNode =
    if dropType == "monsters":
        action("fight")["data"]["fight"]["drops"]
    else:
        action("gathering")["data"]["details"]["items"]

proc craft(item: string, quantity = 1): JsonNode =
    let item = %* {
        "code": item
    }
    for i in 0..quantity:
        action "crafting", item

proc unequip(slot: string): JsonNode =
    let slot = %* {
        "slot": slot
    }
    action "unequip", slot

proc equip(code, slot: string): JsonNode =
    let item = %* {
        "code": code,
        "slot": slot
    }
    unequip slot
    action "equip", item

proc moveTo(pos: (int, int)): JsonNode =
    let position = %* {
        "x": pos[0],
        "y": pos[1]
    }
    action "move", position

# Return the amount of an item in the inventory
proc currentAmount(code: string): int =
    let inventory = readFile("character.json").parseJson["inventory"]

    for item in inventory:
        if item["code"].str == code:
            return item["quantity"].num

proc inventoryFull(): bool = discard

proc depositAll() = discard

# Return the coordinates of a map that contains the resource
proc location(resource: string): (int, int) =
    let map = getJson(fmt"maps/?content_code={resource}")[0]
    return (map["x"].getInt, map["y"].getInt)

proc get(itemCode: string, quantity: int) =
    if inventoryFull():
        depositAll()

    var item = getJson(fmt"items/{itemCode}")["item"]

    if item["craft"].kind != JNull:
        for items in item["craft"]["items"]:
            let neededAmount = items["quantity"].num * quantity 
            let newItem = items["code"].str

            if newItem.currentAmount < neededAmount:
                get(newItem, neededAmount - newItem.currentAmount)
                
        let skillUsed = item["craft"]["skill"].str
        moveTo location skillUsed
        craft itemCode, quantity
        return

    let map = 
        if item["subtype"].str in ["mob", "food"]:
            "monsters"
        else:
            "resources"

    moveTo location map.hasDrop(itemCode)

    var gathered = 0
    while gathered < quantity:    
        for drop in map.gather:
            if drop["code"].str == itemCode:
                inc gathered
    
proc main = discard

when isMainModule:
    main()
