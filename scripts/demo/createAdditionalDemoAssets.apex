System.debug('========== CREATING ADDITIONAL MILLTRACK DEMO ASSETS ==========');


// ============================================================
// 1. FIND THE FIVE EXISTING CUSTOMER ACCOUNTS
// ============================================================

Set<String> accountNames = new Set<String>{
    'Apex Prosthetics Lab Ltd.',
    'Lakeshore Dental Milling Inc.',
    'Maple Ridge Dental Technologies Inc.',
    'NorthStar Dental Milling Ltd.',
    'Precision Smile Studio Inc.'
};

List<Account> accounts = [
    SELECT Id, Name
    FROM Account
    WHERE Name IN :accountNames
];

if (accounts.size() != 5) {
    throw new IllegalArgumentException(
        'Expected 5 customer Accounts but found ' + accounts.size() +
        '. Check Account names before continuing.'
    );
}

Map<String, Id> accountIdsByName = new Map<String, Id>();
Set<Id> accountIds = new Set<Id>();

for (Account acc : accounts) {
    accountIdsByName.put(acc.Name, acc.Id);
    accountIds.add(acc.Id);
    System.debug('ACCOUNT FOUND: ' + acc.Name + ' | ' + acc.Id);
}


// ============================================================
// 2. FIND ACTIVE EXPERIENCE CLOUD CONTACT FOR EACH ACCOUNT
//
// External Salesforce users have a ContactId.
// This means we don't need to hard-code Maya / Olivia / etc.
// ============================================================

List<User> externalUsers = [
    SELECT
        Id,
        Name,
        Username,
        ContactId,
        Contact.Name,
        Contact.AccountId,
        Contact.Account.Name
    FROM User
    WHERE IsActive = true
    AND ContactId != null
    AND Contact.AccountId IN :accountIds
    ORDER BY Contact.Account.Name, Name
];

Map<Id, Id> activeContactByAccount = new Map<Id, Id>();
Map<Id, String> activeContactNameByAccount = new Map<Id, String>();

for (User usr : externalUsers) {

    if (!activeContactByAccount.containsKey(usr.Contact.AccountId)) {

        activeContactByAccount.put(
            usr.Contact.AccountId,
            usr.ContactId
        );

        activeContactNameByAccount.put(
            usr.Contact.AccountId,
            usr.Contact.Name
        );

        System.debug(
            'ACTIVE CUSTOMER USER: ' +
            usr.Contact.Account.Name +
            ' -> ' +
            usr.Contact.Name +
            ' | Username: ' +
            usr.Username
        );
    }
}


// ============================================================
// VERIFY EVERY ACCOUNT HAS AN ACTIVE CUSTOMER CONTACT
// ============================================================

for (Account acc : accounts) {

    if (!activeContactByAccount.containsKey(acc.Id)) {

        throw new IllegalArgumentException(
            'No active Experience Cloud Contact found for Account: ' +
            acc.Name +
            '. Nothing has been inserted.'
        );
    }
}


// ============================================================
// 3. PREPARE NEW ASSETS
// ============================================================

List<Asset> proposedAssets = new List<Asset>{


    // ========================================================
    // APEX PROSTHETICS LAB LTD.
    // Existing:
    //   Apex Roland 53DC
    //   Apex Straumann M Series
    // ========================================================

    new Asset(
        Name = 'Apex Roland 52D',
        AccountId = accountIdsByName.get('Apex Prosthetics Lab Ltd.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Apex Prosthetics Lab Ltd.')
        ),

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-52D',
        Serial_Number__c = 'AP-52D-25118',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2025, 1, 18),
        Last_Service_Date__c = Date.newInstance(2026, 7, 24),

        Warranty_Start_Date__c = Date.newInstance(2025, 1, 18),
        Warranty_End_Date__c = Date.newInstance(2030, 1, 18),

        Description =
            'Five-axis dry milling system used for zirconia, wax and PMMA restorative production.'
    ),

    new Asset(
        Name = 'Apex Ceramill Motion 2',
        AccountId = accountIdsByName.get('Apex Prosthetics Lab Ltd.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Apex Prosthetics Lab Ltd.')
        ),

        Manufacturer__c = 'Amann Girrbach',
        Model__c = 'Ceramill Motion 2',
        Serial_Number__c = 'AP-CM2-23984',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2023, 9, 14),
        Last_Service_Date__c = Date.newInstance(2026, 6, 19),

        Warranty_Start_Date__c = Date.newInstance(2023, 9, 14),
        Warranty_End_Date__c = Date.newInstance(2028, 9, 14),

        Description =
            'Wet and dry milling system supporting ceramic, composite and zirconia workflows.'
    ),


    // ========================================================
    // LAKESHORE DENTAL MILLING INC.
    // Existing:
    //   Lakeshore Roland 52D
    //   Lakeshore Ceramill Motion 2
    // ========================================================

    new Asset(
        Name = 'Lakeshore Roland 53DC',
        AccountId = accountIdsByName.get('Lakeshore Dental Milling Inc.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Lakeshore Dental Milling Inc.')
        ),

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-53DC',
        Serial_Number__c = 'LS-53DC-24631',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 6, 21),
        Last_Service_Date__c = Date.newInstance(2026, 8, 7),

        Warranty_Start_Date__c = Date.newInstance(2024, 6, 21),
        Warranty_End_Date__c = Date.newInstance(2029, 6, 21),

        Description =
            'Automated disc-changing dry mill supporting extended and overnight zirconia production.'
    ),

    new Asset(
        Name = 'Lakeshore Straumann M Series',
        AccountId = accountIdsByName.get('Lakeshore Dental Milling Inc.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Lakeshore Dental Milling Inc.')
        ),

        Manufacturer__c = 'Straumann',
        Model__c = 'M Series',
        Serial_Number__c = 'LS-MSER-22745',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2022, 11, 9),
        Last_Service_Date__c = Date.newInstance(2026, 5, 28),

        Warranty_Start_Date__c = Date.newInstance(2022, 11, 9),
        Warranty_End_Date__c = Date.newInstance(2027, 11, 9),

        Description =
            'Precision milling platform supporting implant and restorative production.'
    ),


    // ========================================================
    // MAPLE RIDGE DENTAL TECHNOLOGIES INC.
    // Existing:
    //   Maple Ridge Roland 52D
    //   Maple Ridge Ceramill Motion 2
    // ========================================================

    new Asset(
        Name = 'Maple Ridge Roland 53DC',
        AccountId = accountIdsByName.get(
            'Maple Ridge Dental Technologies Inc.'
        ),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get(
                'Maple Ridge Dental Technologies Inc.'
            )
        ),

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-53DC',
        Serial_Number__c = 'MR-53DC-25306',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2025, 3, 11),
        Last_Service_Date__c = Date.newInstance(2026, 8, 16),

        Warranty_Start_Date__c = Date.newInstance(2025, 3, 11),
        Warranty_End_Date__c = Date.newInstance(2030, 3, 11),

        Description =
            'High-capacity automated dry milling unit used for unattended production cycles.'
    ),

    new Asset(
        Name = 'Maple Ridge Straumann M Series',
        AccountId = accountIdsByName.get(
            'Maple Ridge Dental Technologies Inc.'
        ),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get(
                'Maple Ridge Dental Technologies Inc.'
            )
        ),

        Manufacturer__c = 'Straumann',
        Model__c = 'M Series',
        Serial_Number__c = 'MR-MSER-24157',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 1, 29),
        Last_Service_Date__c = Date.newInstance(2026, 7, 9),

        Warranty_Start_Date__c = Date.newInstance(2024, 1, 29),
        Warranty_End_Date__c = Date.newInstance(2029, 1, 29),

        Description =
            'Precision milling system used for digital implant and restorative workflows.'
    ),


    // ========================================================
    // NORTHSTAR DENTAL MILLING LTD.
    // Existing:
    //   NorthStar Roland 53DC
    //   NorthStar Ceramill Motion 2
    // ========================================================

    new Asset(
        Name = 'NorthStar Roland 52D',
        AccountId = accountIdsByName.get('NorthStar Dental Milling Ltd.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('NorthStar Dental Milling Ltd.')
        ),

        Manufacturer__c = 'Roland',
        Model__c = 'DWX-52D',
        Serial_Number__c = 'NS-52D-22862',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2022, 8, 15),
        Last_Service_Date__c = Date.newInstance(2026, 6, 11),

        Warranty_Start_Date__c = Date.newInstance(2022, 8, 15),
        Warranty_End_Date__c = Date.newInstance(2027, 8, 15),

        Description =
            'Five-axis dry mill used for routine crown, bridge and zirconia production.'
    ),

    new Asset(
        Name = 'NorthStar Straumann M Series',
        AccountId = accountIdsByName.get('NorthStar Dental Milling Ltd.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('NorthStar Dental Milling Ltd.')
        ),

        Manufacturer__c = 'Straumann',
        Model__c = 'M Series',
        Serial_Number__c = 'NS-MSER-25073',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2025, 2, 3),
        Last_Service_Date__c = Date.newInstance(2026, 8, 20),

        Warranty_Start_Date__c = Date.newInstance(2025, 2, 3),
        Warranty_End_Date__c = Date.newInstance(2030, 2, 3),

        Description =
            'Digital milling system dedicated to precision restorative and implant workflows.'
    ),


    // ========================================================
    // PRECISION SMILE STUDIO INC.
    // Existing:
    //   Precision Roland 52D
    //   Precision Roland 53DC
    // ========================================================

    new Asset(
        Name = 'Precision Straumann M Series',
        AccountId = accountIdsByName.get('Precision Smile Studio Inc.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Precision Smile Studio Inc.')
        ),

        Manufacturer__c = 'Straumann',
        Model__c = 'M Series',
        Serial_Number__c = 'PS-MSER-23618',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2023, 6, 12),
        Last_Service_Date__c = Date.newInstance(2026, 7, 31),

        Warranty_Start_Date__c = Date.newInstance(2023, 6, 12),
        Warranty_End_Date__c = Date.newInstance(2028, 6, 12),

        Description =
            'Precision milling platform supporting implant restorations and advanced digital workflows.'
    ),

    new Asset(
        Name = 'Precision Ceramill Motion 2',
        AccountId = accountIdsByName.get('Precision Smile Studio Inc.'),
        ContactId = activeContactByAccount.get(
            accountIdsByName.get('Precision Smile Studio Inc.')
        ),

        Manufacturer__c = 'Amann Girrbach',
        Model__c = 'Ceramill Motion 2',
        Serial_Number__c = 'PS-CM2-24891',
        Machine_Status__c = 'Active',

        Install_Date__c = Date.newInstance(2024, 10, 7),
        Last_Service_Date__c = Date.newInstance(2026, 8, 13),

        Warranty_Start_Date__c = Date.newInstance(2024, 10, 7),
        Warranty_End_Date__c = Date.newInstance(2029, 10, 7),

        Description =
            'Multi-purpose wet and dry milling system used for ceramic and composite restorations.'
    )
};


// ============================================================
// 4. PREVENT ACCIDENTAL DUPLICATES
//
// Serial_Number__c is our unique demo machine identifier.
// If this script gets rerun, existing machines are skipped.
// ============================================================

Set<String> proposedSerials = new Set<String>();

for (Asset machine : proposedAssets) {
    proposedSerials.add(machine.Serial_Number__c);
}

Set<String> existingSerials = new Set<String>();

for (Asset existingMachine : [
    SELECT Serial_Number__c
    FROM Asset
    WHERE Serial_Number__c IN :proposedSerials
]) {
    existingSerials.add(existingMachine.Serial_Number__c);
}


List<Asset> assetsToInsert = new List<Asset>();

for (Asset machine : proposedAssets) {

    if (!existingSerials.contains(machine.Serial_Number__c)) {
        assetsToInsert.add(machine);
    }
    else {
        System.debug(
            'SKIPPING EXISTING ASSET SERIAL: ' +
            machine.Serial_Number__c
        );
    }
}


// ============================================================
// 5. INSERT
// ============================================================

if (!assetsToInsert.isEmpty()) {

    insert assetsToInsert;

    System.debug('');
    System.debug(
        'Successfully created ' +
        assetsToInsert.size() +
        ' new Assets.'
    );
}
else {

    System.debug(
        'No Assets inserted. All proposed serial numbers already exist.'
    );
}


// ============================================================
// 6. SUMMARY
// ============================================================

System.debug('');
System.debug('========== ADDITIONAL DEMO ASSET SUMMARY ==========');

for (Asset machine : assetsToInsert) {

    String customerContact =
        activeContactNameByAccount.get(machine.AccountId);

    System.debug(
        'ASSET: ' +
        machine.Name +
        ' | ' +
        machine.Manufacturer__c +
        ' ' +
        machine.Model__c +
        ' | Serial: ' +
        machine.Serial_Number__c +
        ' | Contact: ' +
        customerContact +
        ' | ID: ' +
        machine.Id
    );
}

System.debug(
    '========== ADDITIONAL DEMO ASSET CREATION COMPLETE =========='
);