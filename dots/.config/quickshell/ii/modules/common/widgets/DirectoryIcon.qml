import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

Item {
    id: root
    required property var fileModelData
    property color color: Appearance.colors.colPrimary

    StyledImage {
        id: image
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit

        source: {
            if (!root.fileModelData.fileIsDir)
                return Quickshell.iconPath("application-x-zerosize", true);

            // XDG directory names can be localized; icon names stay in English.
            const directories = [
                [Directories.documents, "folder-documents"],
                [Directories.downloads, "folder-download"],
                [Directories.music, "folder-music"],
                [Directories.pictures, "folder-pictures"],
                [Directories.videos, "folder-videos"]
            ];
            const special = directories.find(dir => FileUtils.trimFileProtocol(dir[0]) === root.fileModelData.filePath);
            return (special ? Quickshell.iconPath(special[1], true) : "")
                || Quickshell.iconPath("folder", true)
                || Quickshell.iconPath("inode-directory", true);
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: root.fileModelData.fileIsDir ? "folder" : "draft"
        iconSize: Math.min(root.width, root.height)
        color: root.color
    }

    Process {
        running: !fileModelData.fileIsDir
        command: ["file", "--mime", "-b", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].replace("/", "-");
                image.source = Images.validImageTypes.some(t => mime === `image-${t}`) ? fileModelData.fileUrl : Quickshell.iconPath(mime, true);
            }
        }
    }
}
