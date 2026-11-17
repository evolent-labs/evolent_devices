local Integrations = { inventories = {} }

Integrations.contract = {
    server = {
        'inventoryReady',
        'inventoryName',
        'keepsMetadata',
        'itemDefined',
        'addItem',
        'removeItem',
        'getSlot',
        'hasItem',
        'canCarry',
        'setMetadata',
        'findItem',
        'onItemCreated',
        'onItemUsed',
        'propertiesReady',
        'propertyKeys',
        'forgetProperty',
    },
    client = {},
}

return Integrations
