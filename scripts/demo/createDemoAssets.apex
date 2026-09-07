// ============================================================
// MillTrack Intelligence
// Demo Data - Assets
//
// Creates:
//   10 Assets
//   2 Assets per demo Account
//
// Each Asset is associated with the Account's designated
// future Experience Cloud Contact.
//
// Safe to re-run: existing demo Assets are skipped based on
// Serial_Number__c.
// ============================================================


// ------------------------------------------------------------
// 1. Load demo Accounts
// ------------------------------------------------------------

Set<String> demoAccountNames = new Set<String>{
    'NorthStar Dental Milling Ltd.',
    'Precision Smile Studio Inc.',
    'Lakeshore Dental Milling Inc.',
    'Apex Prosthetics Lab Ltd.',
    'Maple Ridge Dental Technologies Inc.'
};

Map<String, Account> accountsByName = new Map<String, Account>();

for (Account a : [
    SELECT Id, Name
    FROM Account
    WHERE Name IN :demoAccountNames
]) {
    accountsByName.put(a.Name, a);
}

System.assertEquals(
    5,
    accountsByName.size(),
    'Expected all 5 demo Accounts before creating Assets.'
);


// ------------------------------------------------------------
// 2. Load designated portal Contacts
// ------------------------------------------------------------

Set<String> portalEmails = new Set<String>{
    'priya.mehta@northstardental.example',
    'olivia.chen@precisionsmile.example',
    'aisha.rahman@lakeshoredentalmilling.example',
    'maya.singh@apexprosthetics.example',
    'sophia.patel@mapleridgedental.example'
};

Map<String, Contact> contactsByEmail = new Map<String, Contact>();

for (Contact c : [
    SELECT Id, Email, AccountId, Account.Name
    FROM Contact
    WHERE Email IN :portalEmails
]) {
    contactsByEmail.put(c.Email.toLowerCase(), c);
}

System.assertEquals(
    5,
    contactsByEmail.size(),
    'Expected all 5 designated portal Contacts before creating Assets.'
);


// ------------------------------------------------------------
// 3. Find any Assets already created
// ------------------------------------------------------------

Set<String> demoSerials = new Set<String>{
    'NS-53DC-26017',
    'NS-CM2-24109',
    'PS-53DC-23042',
    'PS-52D-21184',
    'LS-CM2-24063',
    'LS-52D-23127',
    'AP-53DC-23171',
    'AP-MSER-24022',
    'MR-52D-22094',
    'MR-CM2-22148'
};

Set<String> existingSerials = new Set<String>();

for (Asset a : [
    SELECT Serial_Number__c
    FROM Asset
    WHERE Serial_Number__c IN :demoSerials
]) {
    if (a.Serial_Number__c != null) {
        existingSerials.add(a.Serial_Number__c);
    }
}


// ------------------------------------------------------------
// 4. Prepare Assets
// ------------------------------------------------------------

List<Asset> assetsToInsert = new List<Asset>();


// ============================================================
// NorthStar Dental Milling Ltd.
// Primary Contact: Priya Mehta
// ============================================================

if (!existingSerials.contains('NS-53DC-26017')) {
    assetsToInsert.add(new Asset(
        Name = 'NorthStar Roland 53DC',
        AccountId = accountsByName.get(
            'NorthStar Dental Milling Ltd.'
        ).Id,
        ContactId = contactsByEmail.get(
            'priya.mehta@northstardental.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-53DC',
        Serial_Number__c = 'NS-53DC-26017',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 3, 18),

        Warranty_Start_Date__c = Date.newInstance(2024, 3, 18),
        Warranty_End_Date__c = Date.newInstance(2029, 3, 18)
    ));
}

if (!existingSerials.contains('NS-CM2-24109')) {
    assetsToInsert.add(new Asset(
        Name = 'NorthStar Ceramill Motion 2',
        AccountId = accountsByName.get(
            'NorthStar Dental Milling Ltd.'
        ).Id,
        ContactId = contactsByEmail.get(
            'priya.mehta@northstardental.example'
        ).Id,

        Manufacturer__c = 'Amann Girrbach',
        Model__c = 'Ceramill Motion 2',
        Serial_Number__c = 'NS-CM2-24109',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2023, 9, 11),

        Warranty_Start_Date__c = Date.newInstance(2023, 9, 11),
        Warranty_End_Date__c = Date.newInstance(2028, 9, 11)
    ));
}


// ============================================================
// Precision Smile Studio Inc.
// Primary Contact: Olivia Chen
// ============================================================

if (!existingSerials.contains('PS-53DC-23042')) {
    assetsToInsert.add(new Asset(
        Name = 'Precision Roland 53DC',
        AccountId = accountsByName.get(
            'Precision Smile Studio Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'olivia.chen@precisionsmile.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-53DC',
        Serial_Number__c = 'PS-53DC-23042',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2022, 11, 7),

        Warranty_Start_Date__c = Date.newInstance(2022, 11, 7),
        Warranty_End_Date__c = Date.newInstance(2027, 11, 7)
    ));
}

if (!existingSerials.contains('PS-52D-21184')) {
    assetsToInsert.add(new Asset(
        Name = 'Precision Roland 52D',
        AccountId = accountsByName.get(
            'Precision Smile Studio Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'olivia.chen@precisionsmile.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-52D',
        Serial_Number__c = 'PS-52D-21184',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2021, 5, 24),

        Warranty_Start_Date__c = Date.newInstance(2021, 5, 24),
        Warranty_End_Date__c = Date.newInstance(2026, 5, 24)
    ));
}


// ============================================================
// Lakeshore Dental Milling Inc.
// Primary Contact: Aisha Rahman
// ============================================================

if (!existingSerials.contains('LS-CM2-24063')) {
    assetsToInsert.add(new Asset(
        Name = 'Lakeshore Ceramill Motion 2',
        AccountId = accountsByName.get(
            'Lakeshore Dental Milling Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'aisha.rahman@lakeshoredentalmilling.example'
        ).Id,

        Manufacturer__c = 'Amann Girrbach',
        Model__c = 'Ceramill Motion 2',
        Serial_Number__c = 'LS-CM2-24063',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 6, 3),

        Warranty_Start_Date__c = Date.newInstance(2024, 6, 3),
        Warranty_End_Date__c = Date.newInstance(2029, 6, 3)
    ));
}

if (!existingSerials.contains('LS-52D-23127')) {
    assetsToInsert.add(new Asset(
        Name = 'Lakeshore Roland 52D',
        AccountId = accountsByName.get(
            'Lakeshore Dental Milling Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'aisha.rahman@lakeshoredentalmilling.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-52D',
        Serial_Number__c = 'LS-52D-23127',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2023, 2, 13),

        Warranty_Start_Date__c = Date.newInstance(2023, 2, 13),
        Warranty_End_Date__c = Date.newInstance(2028, 2, 13)
    ));
}


// ============================================================
// Apex Prosthetics Lab Ltd.
// Primary Contact: Maya Singh
// ============================================================

if (!existingSerials.contains('AP-53DC-23171')) {
    assetsToInsert.add(new Asset(
        Name = 'Apex Roland 53DC',
        AccountId = accountsByName.get(
            'Apex Prosthetics Lab Ltd.'
        ).Id,
        ContactId = contactsByEmail.get(
            'maya.singh@apexprosthetics.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-53DC',
        Serial_Number__c = 'AP-53DC-23171',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2023, 7, 17),

        Warranty_Start_Date__c = Date.newInstance(2023, 7, 17),
        Warranty_End_Date__c = Date.newInstance(2028, 7, 17)
    ));
}

if (!existingSerials.contains('AP-MSER-24022')) {
    assetsToInsert.add(new Asset(
        Name = 'Apex Straumann M Series',
        AccountId = accountsByName.get(
            'Apex Prosthetics Lab Ltd.'
        ).Id,
        ContactId = contactsByEmail.get(
            'maya.singh@apexprosthetics.example'
        ).Id,

        Manufacturer__c = 'Straumann',
        Model__c = 'M Series',
        Serial_Number__c = 'AP-MSER-24022',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 1, 22),

        Warranty_Start_Date__c = Date.newInstance(2024, 1, 22),
        Warranty_End_Date__c = Date.newInstance(2029, 1, 22)
    ));
}


// ============================================================
// Maple Ridge Dental Technologies Inc.
// Primary Contact: Sophia Patel
// ============================================================

if (!existingSerials.contains('MR-52D-22094')) {
    assetsToInsert.add(new Asset(
        Name = 'Maple Ridge Roland 52D',
        AccountId = accountsByName.get(
            'Maple Ridge Dental Technologies Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'sophia.patel@mapleridgedental.example'
        ).Id,

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-52D',
        Serial_Number__c = 'MR-52D-22094',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2022, 4, 4),
        InstallDate = Date.newInstance(2022, 4, 4),

        Warranty_Start_Date__c = Date.newInstance(2022, 4, 4),
        Warranty_End_Date__c = Date.newInstance(2027, 4, 4)
    ));
}

if (!existingSerials.contains('MR-CM2-22148')) {
    assetsToInsert.add(new Asset(
        Name = 'Maple Ridge Ceramill Motion 2',
        AccountId = accountsByName.get(
            'Maple Ridge Dental Technologies Inc.'
        ).Id,
        ContactId = contactsByEmail.get(
            'sophia.patel@mapleridgedental.example'
        ).Id,

        Manufacturer__c = 'Amann Girrbach',
        Model__c = 'Ceramill Motion 2',
        Serial_Number__c = 'MR-CM2-22148',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2022, 10, 10),

        Warranty_Start_Date__c = Date.newInstance(2022, 10, 10),
        Warranty_End_Date__c = Date.newInstance(2027, 10, 10)
    ));
}


// ------------------------------------------------------------
// 5. Insert
// ------------------------------------------------------------

if (!assetsToInsert.isEmpty()) {
    insert assetsToInsert;
}

System.debug(
    'Inserted ' +
    assetsToInsert.size() +
    ' demo Assets.'
);