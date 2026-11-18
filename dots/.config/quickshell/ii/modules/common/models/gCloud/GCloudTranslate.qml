import QtQuick
import qs.services

GCloudApi {
    function translateStrings(strings: list<string>) {
        startRequest({operation: "translate", language: Translation.languageCode, contents: Array.from(strings)});
    }
}
