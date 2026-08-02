//
//  ProjectKeyTests.swift
//  NotchwatchKitTests
//
//  The name a working directory is filed under. Getting it wrong hides a whole
//  project: the transcript is looked for where nothing was ever written, the
//  session is dropped, and the app goes on looking like it is working.
//

@testable import NotchwatchKit
import Testing

@Suite("Project keys")
struct ProjectKeyTests {
    /// The regression. This repository is checked out under a dot-directory, and
    /// escaping only the separators produced `-hypomnemata-.repos-` while Claude
    /// Code had written `-hypomnemata--repos-`. Every session in `.repos`,
    /// `.config`, or any dotfiles checkout was invisible.
    @Test("a dot is escaped like a separator")
    func dotIsEscapedLikeASeparator() {
        #expect(
            ProjectKey.encode("/Users/sanchpet/hypomnemata/.repos/github/notchwatch")
                == "-Users-sanchpet-hypomnemata--repos-github-notchwatch"
        )
        #expect(ProjectKey.encode("/Users/dev/Yandex.Disk.localized/notes") == "-Users-dev-Yandex-Disk-localized-notes")
    }

    /// Every character outside `[a-zA-Z0-9]` goes the same way — the escaping is
    /// a character class, not a list of separators, so nothing else needs a case
    /// of its own here or in the encoder.
    @Test("every non-alphanumeric character becomes a dash")
    func everyNonAlphanumericBecomesADash() {
        #expect(ProjectKey.encode("/Users/dev/my_project (2)") == "-Users-dev-my-project--2-")
        #expect(ProjectKey.encode("/tmp/a+b@c") == "-tmp-a-b-c")
        // Non-ASCII is not alphanumeric to a JavaScript character class, and a
        // character outside the basic plane is two code units, so two dashes:
        // six Cyrillic letters give six dashes, one emoji gives two.
        #expect(ProjectKey.encode("/Users/dev/проект") == "-Users-dev" + String(repeating: "-", count: 7))
        #expect(ProjectKey.encode("/tmp/🙂") == "-tmp" + String(repeating: "-", count: 3))
    }

    /// Case is kept: Claude Code writes the path as given, and two projects that
    /// differ only in case are two directories.
    @Test("case survives encoding")
    func caseSurvivesEncoding() {
        #expect(ProjectKey.encode("/Users/sanchpet/Git/IWE") == "-Users-sanchpet-Git-IWE")
    }

    /// The mapping is many-to-one: a dash already in the path is indistinguishable
    /// from an escaped separator, so decoding invents separators that were never
    /// there. That is tolerable only because nothing downstream treats the result
    /// as the real directory — the transcript's own `cwd` does that.
    @Test("a dash in a directory name is not recoverable")
    func dashInADirectoryNameIsNotRecoverable() {
        let real = "/Users/dev/cert-manager-webhook/src"
        let key = ProjectKey.encode(real)

        #expect(key == "-Users-dev-cert-manager-webhook-src")
        #expect(ProjectKey.decode(key) == "/Users/dev/cert/manager/webhook/src")
        #expect(ProjectKey.decode(key) != real)

        // Lossy, but still the same project: the key is what the lookup uses, and
        // the invented path encodes back to it.
        #expect(ProjectKey.matches(directoryName: key, workspacePath: ProjectKey.decode(key)))
    }

    /// What decoding is actually for. A terminal session is keyed off the
    /// directory name, so the path it carries is a guess — and the guess has to
    /// lead back to the directory it came from, or the session it keys would find
    /// no transcript. Real names, including the dot-directory case.
    @Test("a decoded directory name encodes back to itself")
    func decodeRoundTripsThroughEncode() {
        let names = [
            "-Users-sanchpet-hypomnemata",
            "-Users-sanchpet-hypomnemata--repos-homelab",
            "-Users-sanchpet-hypomnemata--repos-github-cert-manager-webhook-spaceweb",
            "-Users-sanchpet-Git-IWE",
            "-tmp-iwe-restore-test",
        ]

        for name in names {
            #expect(ProjectKey.encode(ProjectKey.decode(name)) == name)
        }
    }

    /// A relative or bare name still decodes to an absolute path — everything
    /// downstream treats it as one, and `URL(fileURLWithPath:)` would otherwise
    /// resolve it against the app's own working directory.
    @Test("decoding yields an absolute path")
    func decodingYieldsAnAbsolutePath() {
        #expect(ProjectKey.decode("-Users-dev-app") == "/Users/dev/app")
        #expect(ProjectKey.decode("Users-dev-app") == "/Users/dev/app")
    }

    /// The filesystem the direct lookup asks is case-insensitive, so a session
    /// reported with a differently-cased path is the same project. Matching by
    /// string equality alone would send it to the fallback and then to nothing.
    @Test("matching a directory ignores case")
    func matchingIgnoresCase() {
        #expect(ProjectKey.matches(directoryName: "-Users-dev-App", workspacePath: "/users/DEV/app"))
        #expect(ProjectKey.matches(directoryName: "-Users-dev-App", workspacePath: "/Users/dev/other") == false)
    }

    /// Beyond 200 characters Claude Code truncates the name and appends a hash of
    /// the full path. The hash is not reproducible here, so the surviving prefix
    /// is all there is to match on — and a name that was *not* truncated must
    /// still match itself.
    @Test("an over-long key is matched by its prefix")
    func overLongKeyIsMatchedByItsPrefix() {
        let path = "/Users/dev/" + String(repeating: "abcdefghij/", count: 30)
        let key = ProjectKey.encode(path)
        #expect(key.count > ProjectKey.maximumLength)

        let truncated = String(key.prefix(ProjectKey.maximumLength)) + "-1a2b3c"
        #expect(ProjectKey.matches(directoryName: truncated, workspacePath: path))
        #expect(ProjectKey.matches(directoryName: key, workspacePath: path))

        // Weakened, and knowingly: two projects whose paths agree for 200
        // characters are indistinguishable this way, since the hash that would
        // separate them cannot be recomputed. A path that differs inside the
        // prefix — which is every ordinary case — is still rejected.
        #expect(ProjectKey.matches(directoryName: truncated, workspacePath: "/Users/other/" + path) == false)
    }
}
