import Testing
@testable import RoomModel

@Test func categoryRoundTripsThroughRawValue() {
    for category in FurnitureCategory.knownCases {
        #expect(FurnitureCategory(rawValue: category.rawValue) == category)
    }
}

@Test func unknownRawValueIsPreservedRatherThanLost() {
    let category = FurnitureCategory(rawValue: "hoverboardDock")
    #expect(category == .unknown("hoverboardDock"))
    #expect(category.rawValue == "hoverboardDock")
}

@Test func everyKnownCategoryHasAFrenchDisplayName() {
    for category in FurnitureCategory.knownCases {
        #expect(!category.displayName.isEmpty)
        #expect(category.displayName != category.rawValue)
    }
}

@Test func unknownCategoryDisplaysAsGenericFurniture() {
    #expect(FurnitureCategory.unknown("hoverboardDock").displayName == "Meuble")
}
