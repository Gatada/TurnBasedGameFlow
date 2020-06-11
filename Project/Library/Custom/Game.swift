//
//  Game.swift
//  TurnBasedGameFlow
//
//  Created by Johan Basberg on 10/06/2020.
//  Copyright © 2020 Johan Basberg. All rights reserved.
//

import Foundation


/// A card is played each time a Player resolves their turn.
///
/// When the cards run out, the game is over.
enum Card: Int, CaseIterable, Codable {
    case ace
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case ten
    case jack
    case queen
    case king
}

/// Errors encountered when handling Game.
enum GameError: Error {
    
    /// Error thrown when an attempt to decode a `Game` istance failed.
    case failedToDecodeData
}


/// A skeleton Game class to retain game state.
///
/// The game ends when each player has played their last card.
class Game: Codable {
    
    // MARK: - Properties
    
    /// A unqiue identifier for a match.
    private let matchID: String
    
    /// The full deck of cards.
    ///
    /// When a card is played, a new is drafted from the deck.
    private var deck: [Card]?
    
    /// All the turns by the players.
    ///
    /// Each player does a single
    private var turns: [Card]?

    /// Cards dealth to the players.
    ///
    /// Players can change their own card by carrying out an exchange.
    /// When resolving a turn the card is obtained from the last entry in this array,
    /// according to their player position.
    private var playerCards = [[Int: Card]]()
    

    // MARK: - Life Cycle
    
    init?(matchID: String, playerCount: Int) {
        
        self.matchID = matchID
        self.deck = Card.allCases
        
        // Deal the first card to the table.
        guard let randomCard = randomCardFromDeck() else {
            assertionFailure("Failed to draw a random card from the deck.")
            return nil
        }
        turns = [randomCard]
        deck?.removeAll(where: { $0 == randomCard })

        // Deal one card to each player:
        var hand = [Int: Card]()
        for index in 0 ..< playerCount {
            guard let randomCard = randomCardFromDeck() else {
                assertionFailure("Failed to draw a random card from the deck.")
                return nil
            }
            hand[index] = randomCard
            deck?.removeAll(where: { $0 == randomCard })
        }
        playerCards.append(hand)
    }
    
    init?(matchID: String, with data: Data) {
        self.matchID = matchID
        do {
          try update(with: data)
        } catch {
            // Failed to decode data
            return nil
        }
    }
    
    public func update(with data: Data) throws {
        guard let restored = try? JSONDecoder().decode(Game.self, from: data) else {
            assertionFailure("Failed to decode data to Game instance.")
            throw GameError.failedToDecodeData
        }
        
        self.playerCards = restored.playerCards
        self.turns = restored.turns
        self.deck = restored.deck
    }
    
    // MARK: - Helpers
    
    /// Draw a random card from the deck.
    ///
    /// The drawn card is removed from the deck.
    func randomCardFromDeck() -> Card? {
        guard let fullDeck = deck, let randomCard = fullDeck.randomElement() else {
            assertionFailure("Failed to draw a random card from the deck")
            return nil
        }
        deck?.removeAll(where: { $0 == randomCard })
        return randomCard
    }
    
    // MARK: - Game State
    
    func cardForPlayerIndex(_ index: Int) -> Card? {
        guard let currentHand = playerCards.last else {
            assertionFailure("No cards dealt to the players")
            return nil
        }
        return currentHand[index]
    }
    
    // MARK: - Game Updates
    
    /// Called to resolve a turn using the current
    public func resolveTurn(_ turn: Card) {
        turns?.append(turn)
        deck?.removeAll(where: { $0 == turn })
    }
    
    /// Called to set the cards currently held by the players.
    public func resolveExchange(_ newPlayerCards: [Int: Card]) {
        playerCards.append(newPlayerCards)
    }
    
}
