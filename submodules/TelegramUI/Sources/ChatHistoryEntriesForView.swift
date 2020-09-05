import Foundation
import Postbox
import TelegramCore
import SyncCore
import TemporaryCachedPeerDataManager
import Emoji
import AccountContext
import TelegramPresentationData


func chatHistoryEntriesForView(location: ChatLocation, view: MessageHistoryView, includeUnreadEntry: Bool, includeEmptyEntry: Bool, includeChatInfoEntry: Bool, includeSearchEntry: Bool, reverse: Bool, groupMessages: Bool, selectedMessages: Set<MessageId>?, presentationData: ChatPresentationData, historyAppearsCleared: Bool, associatedData: ChatMessageItemAssociatedData, updatingMedia: [MessageId: ChatUpdatingMessageMedia]) -> [ChatHistoryEntry] {
    if historyAppearsCleared {
        return []
    }
    var entries: [ChatHistoryEntry] = []
    var adminRanks: [PeerId: CachedChannelAdminRank] = [:]
    var stickersEnabled = true
    if case let .peer(peerId) = location, peerId.namespace == Namespaces.Peer.CloudChannel {
        for additionalEntry in view.additionalData {
            if case let .cacheEntry(id, data) = additionalEntry {
                if id == cachedChannelAdminRanksEntryId(peerId: peerId), let data = data as? CachedChannelAdminRanks {
                    adminRanks = data.ranks
                }
            } else if case let .peer(_, peer) = additionalEntry, let channel = peer as? TelegramChannel {
                if let defaultBannedRights = channel.defaultBannedRights, defaultBannedRights.flags.contains(.banSendStickers) {
                    stickersEnabled = false
                }
            }
        }
    }

    var groupBucket: [(Message, Bool, ChatHistoryMessageSelection, ChatMessageEntryAttributes)] = []
    loop: for entry in view.entries {
        var contentTypeHint: ChatMessageEntryContentType = .generic
        
        for media in entry.message.media {
            if media is TelegramMediaDice {
                contentTypeHint = .animatedEmoji
            }
            if let action = media as? TelegramMediaAction {
                switch action.action {
                    case .channelMigratedFromGroup, .groupMigratedToChannel, .historyCleared:
                        continue loop
                    default:
                        break
                }
            }
        }
    
        var adminRank: CachedChannelAdminRank?
        if let author = entry.message.author {
            adminRank = adminRanks[author.id]
        }
        
        
        if presentationData.largeEmoji, entry.message.media.isEmpty {
            if stickersEnabled && entry.message.text.count == 1, let _ = associatedData.animatedEmojiStickers[entry.message.text.basicEmoji.0] {
                contentTypeHint = .animatedEmoji
            } else if entry.message.text.count < 10 && messageIsElligibleForLargeEmoji(entry.message) {
                contentTypeHint = .largeEmoji
            }
        }
    
        if groupMessages {
            if !groupBucket.isEmpty && entry.message.groupInfo != groupBucket[0].0.groupInfo {
                entries.append(.MessageGroupEntry(groupBucket[0].0.groupInfo!, groupBucket, presentationData))
                groupBucket.removeAll()
            }
            if let _ = entry.message.groupInfo {
                let selection: ChatHistoryMessageSelection
                if let selectedMessages = selectedMessages {
                    selection = .selectable(selected: selectedMessages.contains(entry.message.id))
                } else {
                    selection = .none
                }
                groupBucket.append((entry.message, entry.isRead, selection, ChatMessageEntryAttributes(rank: adminRank, isContact: entry.attributes.authorIsContact, contentTypeHint: contentTypeHint, updatingMedia: updatingMedia[entry.message.id])))
            } else {
                let selection: ChatHistoryMessageSelection
                if let selectedMessages = selectedMessages {
                    selection = .selectable(selected: selectedMessages.contains(entry.message.id))
                } else {
                    selection = .none
                }
                entries.append(.MessageEntry(entry.message, presentationData, entry.isRead, entry.monthLocation, selection, ChatMessageEntryAttributes(rank: adminRank, isContact: entry.attributes.authorIsContact, contentTypeHint: contentTypeHint, updatingMedia: updatingMedia[entry.message.id])))
            }
        } else {
            let selection: ChatHistoryMessageSelection
            if let selectedMessages = selectedMessages {
                selection = .selectable(selected: selectedMessages.contains(entry.message.id))
            } else {
                selection = .none
            }
            entries.append(.MessageEntry(entry.message, presentationData, entry.isRead, entry.monthLocation, selection, ChatMessageEntryAttributes(rank: adminRank, isContact: entry.attributes.authorIsContact, contentTypeHint: contentTypeHint, updatingMedia: updatingMedia[entry.message.id])))
        }
    }
    
    if !groupBucket.isEmpty {
        assert(groupMessages)
        entries.append(.MessageGroupEntry(groupBucket[0].0.groupInfo!, groupBucket, presentationData))
    }
    
    if let maxReadIndex = view.maxReadIndex, includeUnreadEntry {
        var i = 0
        let unreadEntry: ChatHistoryEntry = .UnreadEntry(maxReadIndex, presentationData)
        for entry in entries {
            if entry > unreadEntry {
                if i != 0 {
                    entries.insert(unreadEntry, at: i)
                }
                break
            }
            i += 1
        }
    }
    
    if case let .replyThread(messageId, isChannelPost, _) = location, !isChannelPost {
        loop: for entry in view.additionalData {
            switch entry {
            case let .message(id, message) where id == messageId:
                if let message = message {
                    let selection: ChatHistoryMessageSelection
                    if let selectedMessages = selectedMessages {
                        selection = .selectable(selected: selectedMessages.contains(message.id))
                    } else {
                        selection = .none
                    }
                    
                    var adminRank: CachedChannelAdminRank?
                    if let author = message.author {
                        adminRank = adminRanks[author.id]
                    }
                    
                    var contentTypeHint: ChatMessageEntryContentType = .generic
                    if presentationData.largeEmoji, message.media.isEmpty {
                        if stickersEnabled && message.text.count == 1, let _ = associatedData.animatedEmojiStickers[message.text.basicEmoji.0] {
                            contentTypeHint = .animatedEmoji
                        } else if message.text.count < 10 && messageIsElligibleForLargeEmoji(message) {
                            contentTypeHint = .largeEmoji
                        }
                    }
                    
                    
                    entries.insert(.MessageEntry(message, presentationData, false, nil, selection, ChatMessageEntryAttributes(rank: adminRank, isContact: false, contentTypeHint: contentTypeHint, updatingMedia: updatingMedia[message.id])), at: 0)
                }
                break loop
            default:
                break
            }
        }
    }
    
    if includeChatInfoEntry {
        if view.earlierId == nil {
            var cachedPeerData: CachedPeerData?
            for entry in view.additionalData {
                if case let .cachedPeerData(_, data) = entry {
                    cachedPeerData = data
                    break
                }
            }
            if let cachedPeerData = cachedPeerData as? CachedUserData, let botInfo = cachedPeerData.botInfo, !botInfo.description.isEmpty {
                entries.insert(.ChatInfoEntry(botInfo.description, presentationData), at: 0)
            } else {
                var isEmpty = true
                if entries.count <= 3 {
                    loop: for entry in view.entries {
                        var isEmptyMedia = false
                        for media in entry.message.media {
                            if let action = media as? TelegramMediaAction {
                                switch action.action {
                                    case .groupCreated, .photoUpdated, .channelMigratedFromGroup, .groupMigratedToChannel:
                                        isEmptyMedia = true
                                    default:
                                        break
                                }
                            }
                        }
                        var isCreator = false
                        if let peer = entry.message.peers[entry.message.id.peerId] as? TelegramGroup, case .creator = peer.role {
                            isCreator = true
                        } else if let peer = entry.message.peers[entry.message.id.peerId] as? TelegramChannel, case .group = peer.info, peer.flags.contains(.isCreator) {
                            isCreator = true
                        }
                        if isEmptyMedia && isCreator {
                        } else {
                            isEmpty = false
                            break loop
                        }
                    }
                } else {
                    isEmpty = false
                }
                if isEmpty {
                    entries.removeAll()
                }
            }
        }
    } else if includeSearchEntry {
        if view.laterId == nil {
            if !view.entries.isEmpty {
                entries.append(.SearchEntry(presentationData.theme.theme, presentationData.strings))
            }
        }
    }
    
    if reverse {
        return entries.reversed()
    } else {
        return entries
    }
}
