pragma Singleton
import Quickshell

Singleton {
    id: root

    // QML lists (e.g. list<string> config options): a length and only numeric keys.
    // Empty ones count too, or they would be saved as {} instead of [].
    function isQtArrayLike(obj) {
        return !!obj && typeof obj === "object" &&
            typeof obj.length === "number" &&
            Object.keys(obj).every(key => !isNaN(key) || key === "length");
    }

    function toPlainObject(qtObj) {
        if (qtObj === null || typeof qtObj !== "object") return qtObj;

        // Handle true arrays
        if (Array.isArray(qtObj)) {
            return qtObj.map(item => toPlainObject(item));
        }

        // Handle array-like Qt objects (e.g., have length and numeric keys)
        if (root.isQtArrayLike(qtObj)) {
            let arr = [];
            for (let i = 0; i < qtObj.length; i++) {
                arr.push(toPlainObject(qtObj[i]));
            }
            return arr;
        }

        const result = ({});
        for (let key in qtObj) {
            if (
                typeof qtObj[key] !== "function" &&
                !key.startsWith("objectName") &&
                !key.startsWith("children") &&
                !key.startsWith("object") &&
                !key.startsWith("parent") &&
                !key.startsWith("metaObject") &&
                !key.startsWith("destroyed") &&
                !key.startsWith("reloadableId")
            ) {
                result[key] = toPlainObject(qtObj[key]);
            }
        }
        // console.log(JSON.stringify(result))
        return result;
    }

    function applyToQtObject(qtObj, jsonObj) {
        // console.log("applyToQtObject", JSON.stringify(qtObj, null, 2), "<<", JSON.stringify(jsonObj, null, 2));
        if (!qtObj || typeof jsonObj !== "object" || jsonObj === null) return;

        const isQtArrayLike = root.isQtArrayLike;

        // If both are arrays or array-like, update in place or replace
        if ((Array.isArray(qtObj) || isQtArrayLike(qtObj)) && Array.isArray(jsonObj)) {
            qtObj.length = 0;
            for (let i = 0; i < jsonObj.length; i++) {
                qtObj.push(jsonObj[i]);
            }
            return;
        }

        // If target is array or array-like but source is not, clear
        if ((Array.isArray(qtObj) || isQtArrayLike(qtObj)) && !Array.isArray(jsonObj)) {
            qtObj.length = 0;
            return;
        }

        // If source is array but target is not, assign directly if possible
        if (!(Array.isArray(qtObj) || isQtArrayLike(qtObj)) && Array.isArray(jsonObj)) {
            return jsonObj;
        }

        for (let key in jsonObj) {
            if (!qtObj.hasOwnProperty(key)) continue;
            const value = qtObj[key];
            const jsonValue = jsonObj[key];
            // console.log("applying to qt obj key:", value, "jsonValue:", jsonValue);
            if ((Array.isArray(value) || isQtArrayLike(value)) && Array.isArray(jsonValue)) {
                value.length = 0;
                for (let i = 0; i < jsonValue.length; i++) {
                    value.push(jsonValue[i]);
                }
            } else if (value && typeof value === "object" && !Array.isArray(value) && !isQtArrayLike(value)) {
                applyToQtObject(value, jsonValue);
            } else {
                qtObj[key] = jsonValue;
            }
        }
    }
}
