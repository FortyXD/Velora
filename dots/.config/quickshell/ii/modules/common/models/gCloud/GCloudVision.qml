import QtQuick
import qs.modules.common.functions

GCloudApi {
    function annotateImage(imageUri: string) {
        startRequest({operation: "vision", path: FileUtils.trimFileProtocol(imageUri)});
    }
}
