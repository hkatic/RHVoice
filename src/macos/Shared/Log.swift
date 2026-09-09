// Copyright (C) 2026 RHVoice contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

import os

/// Unified-logging handles shared by the app and the synthesizer extension.
/// Follow them with:
///   log stream --predicate 'subsystem == "org.rhvoice.RHVoice"' --level debug
enum RHVLog {
    static let subsystem = "org.rhvoice.RHVoice"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let synthesizer = Logger(subsystem: subsystem, category: "synthesizer")
    static let installer = Logger(subsystem: subsystem, category: "installer")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
}
