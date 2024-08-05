{.push discardable, thread, 
experimental: "dotOperators".}

import threadpool, httpclient, json, macros

from sequtils import filterIt
from os import sleep
from strformat import fmt

const 
    # TODO: environment variables
    token = ""

    headers = (
        {"Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": "Bearer " & token})

    grandExchange = (5, 1)
    bank = (4, 1)
    tasksMaster = (1, 2)

# Syntactic sugar for json key access with dot notation
# e.g. json.field instead of json["field"] 
macro `.`(obj: JsonNode, field: untyped): untyped =
    let fieldName = $field
    quote do: 
        if `fieldName` == "first":
            `obj`["data"][0]
        else:
            `obj`[`fieldName`]

type 
    Username = enum user, user2, user3, user4, user5

    User = object
        name: Username
        client: HttpClient

# Forward declaration
proc action(user: User, endpoint: string, payload = %* ""): JsonNode
proc moveTo(user: User, pos: (int, int)): JsonNode

proc config(user: User): JsonNode =
    parseJson readFile ($ user.name & ".json")

proc wait(user: User) =
    sleep user.config.cooldown.num * 1000

proc depositAll(user: User) =
    user.moveTo(bank)

    let items = user.config
        .inventory
        .filterIt it.quantity.num > 0

    for item in items:
        user.action "bank/deposit", %* {
            "code": item.code.str,
            "quantity": item.quantity.num
        }
    
    user.action "bank/deposit/gold", %* {
        "quantity": user.config.gold.num
    }

# Update the current character details
proc update(user: User, data: JsonNode) =
    writeFile(
        $ user.name & ".json", 
        pretty data)

proc handleError(response: JsonNode, user: User, endpoint: string, payload = %* ""): JsonNode =
    case response.error.code.num
    # Server lagging
    of 486, 502:
        sleep 3_000
        user.action(endpoint, payload)
        
    # Inventory full
    of 497:
        user.depositAll()
        user.action(endpoint, payload)

    # Character in cooldown
    of 499:
        user.wait

    else: echo fmt"{user.name} - {response.error.message} on {endpoint}"

proc getJson(endpoint: string): JsonNode =
    newHttpClient(headers = newHttpHeaders headers)
        .request(fmt"{api}/{endpoint}", HttpGet)
        .body
        .parseJson

proc action(user: User, endpoint: string, payload = %* ""): JsonNode =
    result = user.client.request(
        fmt"{api}/my/{user.name}/action/{endpoint}", 
        HttpPost, 
        $payload).body.parseJson
    
    if result.contains("error"):
        return result.handleError(user, endpoint, payload)
    
    user.update result.data.character
    user.wait

proc moveTo(user: User, pos: (int, int)): JsonNode =
    user.action "move", %* {
        "x": pos[0],
        "y": pos[1]
    }

proc craft(user: User, code: string, quantity = 1): JsonNode =
    user.action "crafting", %* {
        "code": code,
        "quantity": quantity
    }

proc equip(user: User, code, slot: string): JsonNode =
    # TODO: Get or withdraw item if not in inventory
    # Empty the slot
    user.action "unequip", %* {
        "slot": slot
    }
    
    user.action "equip", %* {
        "code": code,
        "slot": slot
    }

# Return the amount of an item in the inventory
proc hasAmount(user: User, target: JsonNode): int =
    for item in user.config.inventory:
        if item.code.str == target.code.str:
            return item.quantity.num
        
# Return coordinates of a map that contains the resource
proc location(resource: string): (int, int) =
    let map = getJson(fmt"maps/?content_code={resource}").first
    (map.x.getInt, map.y.getInt)

# Harvest resources on current map
proc harvest(user: User, dropType = "monsters"): JsonNode =
    case dropType
    of "monsters":
        user.action("fight").data.fight.drops
    else:
        user.action("gathering").data.details.items

proc fight(user: User, monster: string, quantity: int) =
    user.moveTo(location monster)

    for i in 0..quantity: 
        user.harvest

proc recycle(user: User, code: string, quantity = 1) =
    let requiredSkill = getJson(fmt"items/{code}").data.item.skill
    user.moveTo location requiredSkill.str

    user.action "recycling", %* {
        "code": code,
        "quantity": quantity
    }

# Returns the current task objective and the progress left to do
proc task(user: User): tuple[target: string, todo: int] =
    (user.config.task.str,
    int user.config.task_total.num - user.config.task_progress.num)

proc newTask(user: User) =
    user.moveTo(tasksMaster)
    
    if user.task.target != "":
        user.action("task/complete")

    user.action("task/new")

proc doTask(user: User) =
    if user.task.todo == 0:
        user.newTask
    
    user.fight(user.task.target, user.task.todo)
    user.newTask

proc gather(user: User, item: JsonNode, quantity: int) =
    # FIXME: Check bank for the resource
    # Decide which endpiont to use (/resources/ or /monsters/)
    let dropType = case item.subtype.str
        of "mob", "food": "monsters"
        else: "resources"

    # Get the first map that drops the resource - TODO: get closest map
    let map = getJson(fmt"{dropType}/?drop={item.code.str}").first
    user.moveTo location map.code.str

    # Gather the resource
    var gathered = 0
    while gathered < quantity:   
        for drop in user.harvest(dropType):
            if drop.code == item.code:
                gathered += drop.quantity.num

proc get(user: User, itemCode: string, totalQuantity: int, recycle = false) =
    var item = getJson(fmt"items/{itemCode}").data.item

    # If the item doesn't have a craft, it's a resource
    if item.craft.kind == JNull:
        user.gather(item, totalQuantity)
        return

    for requiredItem in JsonNode item.craft.items:
        let neededAmount = requiredItem.quantity.num * totalQuantity - user.hasAmount(requiredItem)
        if neededAmount > 0:
            user.get(requiredItem.code.str, neededAmount)
    
    # Move to the correct workshop for the skill
    let requiredSkill = item.craft.skill.str
    user.moveTo location requiredSkill
    
    user.craft itemCode, totalQuantity
    
    if recycle: 
        user.recycle itemCode, totalQuantity

proc init(user: User) =
    user.update getJson(fmt"characters/{user.name}")

    while true:
        user.get("cooked_gudgeon", 20)

proc main() =
    for name in Username:
        spawn User(
                name: name,
                client: newHttpClient(headers = newHttpHeaders(headers))
        ).init
    
    sync()

when isMainModule:
    main()
