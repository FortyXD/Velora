pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * A service for interacting with various booru APIs.
 */
Singleton {
    id: root
    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)
    signal responseFinished()

    property string failMessage: Translation.tr("Nothing found. Tips:\n- Check your tags and the NSFW switch\n- Send an empty search to browse popular images")
    property var responses: []
    property int runningRequests: 0
    property var defaultUserAgent: Config.options?.networking?.userAgent || "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: Object.keys(providers).filter(provider => provider !== "system" && providers[provider].api)
    property var providers: {
        "system": { "name": Translation.tr("System") },
        "wallhaven": {
            "name": "Wallhaven",
            "url": "https://wallhaven.cc",
            "api": "https://wallhaven.cc/api/v1/search",
            "description": Translation.tr("Anime wallpapers | High resolution, reachable without a VPN"),
            "mapFunc": (response) => {
                return response.data.map(item => {
                    return {
                        "id": item.id,
                        "width": item.dimension_x,
                        "height": item.dimension_y,
                        "aspect_ratio": item.dimension_x / item.dimension_y,
                        "tags": `${item.resolution} | ${item.purity}`, // Search results don't include tags
                        "rating": item.purity === "sfw" ? "s" : (item.purity === "sketchy" ? "q" : "e"),
                        "is_nsfw": item.purity !== "sfw",
                        "md5": item.id,
                        "preview_url": item.thumbs.original, // "large" is always cropped to 3:2
                        "sample_url": item.thumbs.original,
                        "file_url": item.path,
                        "file_ext": item.path.split('.').pop(),
                        "source": item.source || item.url,
                    }
                })
            },
            // No tag autocomplete API: suggestions come from recently used tags
        },
        "yandere": {
            "name": "yande.re",
            "url": "https://yande.re",
            "api": "https://yande.re/post.json",
            "description": Translation.tr("All-rounder | Good quality, decent quantity"),
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "konachan": {
            "name": "Konachan",
            "url": "https://konachan.net",
            "api": "https://konachan.net/post.json",
            "description": Translation.tr("For desktop wallpapers | Good quality"),
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=10&name={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "zerochan": {
            "name": "Zerochan",
            "url": "https://www.zerochan.net",
            "api": "https://www.zerochan.net/?json",
            "description": Translation.tr("Clean stuff | Excellent quality, no NSFW"),
            "mapFunc": (response) => {
                response = response.items
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags.join(" "),
                        "rating": "safe", // Zerochan doesn't have nsfw
                        "is_nsfw": false,
                        "md5": item.md5,
                        "preview_url": item.thumbnail,
                        "sample_url": item.thumbnail,
                        "file_url": item.thumbnail,
                        "file_ext": "avif",
                        "source": getWorkingImageSource(item.source) ?? item.thumbnail,
                        "character": item.tag
                    }
                })
            }
        },
        "danbooru": {
            "name": "Danbooru",
            "url": "https://danbooru.donmai.us",
            "api": "https://danbooru.donmai.us/posts.json",
            "description": Translation.tr("The popular one | Best quantity, but quality can vary wildly"),
            "mapFunc": (response) => {
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.image_width,
                        "height": item.image_height,
                        "aspect_ratio": item.image_width / item.image_height,
                        "tags": item.tag_string,
                        "rating": item.rating,
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_file_url,
                        "sample_url": item.file_url ?? item.large_file_url,
                        "file_url": item.large_file_url,
                        "file_ext": item.file_ext,
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://danbooru.donmai.us/tags.json?limit=10&search[name_matches]={{query}}*",
            "tagMapFunc": (response) => {
                return response.map(item => {
                    return {
                        "name": item.name,
                        "count": item.post_count
                    }
                })
            }
        },
        "gelbooru": {
            "name": "Gelbooru",
            "url": "https://gelbooru.com",
            "api": "https://gelbooru.com/index.php?page=dapi&s=post&q=index&json=1",
            "description": Translation.tr("The hentai one | Great quantity, a lot of NSFW, quality varies wildly"),
            "mapFunc": (response) => {
                response = response.post
                return response.map(item => {
                    return {
                        "id": item.id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags,
                        "rating": item.rating.replace('general', 's').charAt(0),
                        "is_nsfw": (item.rating != 's'),
                        "md5": item.md5,
                        "preview_url": item.preview_url,
                        "sample_url": item.sample_url ?? item.file_url,
                        "file_url": item.file_url,
                        "file_ext": item.file_url.split('.').pop(),
                        "source": getWorkingImageSource(item.source) ?? item.file_url,
                    }
                })
            },
            "tagSearchTemplate": "https://gelbooru.com/index.php?page=dapi&s=tag&q=index&json=1&orderby=count&limit=10&name_pattern={{query}}%",
            "tagMapFunc": (response) => {
                return response.tag.map(item => {
                    return {
                        "name": item.name,
                        "count": item.count
                    }
                })
            }
        },
        "waifu.im": {
            "name": "waifu.im",
            "url": "https://waifu.im",
            "api": "https://api.waifu.im/search",
            "description": Translation.tr("Waifus only | Excellent quality, limited quantity"),
            "mapFunc": (response) => {
                response = response.images
                return response.map(item => {
                    return {
                        "id": item.image_id,
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.tags.map(tag => {return tag.name}).join(" "),
                        "rating": item.is_nsfw ? "e" : "s",
                        "is_nsfw": item.is_nsfw,
                        "md5": item.md5,
                        "preview_url": item.sample_url ?? item.url, // preview_url just says access denied (maybe i fucked up and sent too many requests idk)
                        "sample_url": item.url,
                        "file_url": item.url,
                        "file_ext": item.extension,
                        "source": getWorkingImageSource(item.source) ?? item.url,
                    }
                })
            },
            "tagSearchTemplate": "https://api.waifu.im/tags",
            "tagMapFunc": (response) => {
                return [...response.versatile.map(item => {return {"name": item}}),
                    ...response.nsfw.map(item => {return {"name": item}})]
            }
        },
        "t.alcy.cc": {
            "name": "Alcy",
            "url": "https://t.alcy.cc",
            "api": "https://t.alcy.cc/",
            "description": Translation.tr("Large images | God tier quality, no NSFW."),
            "fixedTags": [
                {
                    "name": "ycy",
                    "count": "General"
                },
                {
                    "name": "moez",
                    "count": "Moe"
                },
                {
                    "name": "ysz",
                    "count": "Genshin Impact"
                },
                {
                    "name": "fj",
                    "count": "Landscape"
                },
                {
                    "name": "bd",
                    "count": "Girl on white background"
                },
                {
                    "name": "xhl",
                    "count": "Shiggy"
                },
            ],
            "manualParseFunc": (responseText) => {
                // Alcy just returns image links, each on a new line
                const lines = responseText.trim().split('\n');
                return lines.map(line => {
                    return {
                        "id": Qt.md5(line),
                        // Alcy doesn't provide dimensions and images are often of god resolution
                        "width": 1000,
                        "height": 1000,
                        "aspect_ratio": 1,
                        "tags": "[no tags]",
                        "rating": "s",
                        "is_nsfw": false,
                        "md5": Qt.md5(line),
                        "preview_url": line,
                        "sample_url": line,
                        "file_url": line,
                        "file_ext": line.split('.').pop(),
                        "source": "",
                    }
                });
            },
        }
    }
    property var currentProvider: Persistent.states.booru.provider

    function getWorkingImageSource(url) {
        if (url.includes('pximg.net')) {
            return `https://www.pixiv.net/en/artworks/${url.substring(url.lastIndexOf('/') + 1).replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')}`;
        }
        return url;
    }

    // feedback: post a chat message about the switch (the dropdown only does that when there are notes)
    function setProvider(provider, feedback = true) {
        provider = provider.toLowerCase()
        if (providerList.indexOf(provider) !== -1) {
            Persistent.states.booru.provider = provider
            if (feedback || provider == "zerochan") root.addSystemMessage(Translation.tr("Provider set to ") + providers[provider].name
                + (provider == "zerochan" ? Translation.tr(". Notes for Zerochan:\n- You must enter a color\n- Set your zerochan username in `sidebar.booru.zerochan.username` config option. You [might be banned for not doing so](https://www.zerochan.net/api#:~:text=The%20request%20may%20still%20be%20completed%20successfully%20without%20this%20custom%20header%2C%20but%20your%20project%20may%20be%20banned%20for%20being%20anonymous.)!") : ""))
        } else {
            root.addSystemMessage(Translation.tr("Invalid API provider. Supported: \n- ") + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        responses = []
    }

    function addSystemMessage(message) {
        responses = [...responses, root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": `${message}`
        })]
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1, providerId=currentProvider) {
        var provider = providers[providerId]
        var baseUrl = provider.api
        var url = baseUrl
        var tagString = tags.join(" ")
        if (!nsfw && !(["zerochan", "waifu.im", "t.alcy.cc", "wallhaven"].includes(providerId))) {
            if (providerId == "gelbooru")
                tagString += " rating:general";
            else
                tagString += " rating:safe";
        }
        var params = []
        // Tags & limit
        if (providerId === "wallhaven") {
            // Anime category; NSFW only unlocks "sketchy" (the explicit tier needs an API key). Page size is fixed at 24.
            if (tagString.length > 0) {
                params.push("q=" + encodeURIComponent(tagString))
                params.push("sorting=relevance")
            } else {
                params.push("sorting=toplist")
                params.push("topRange=1M")
            }
            params.push("categories=010")
            params.push("purity=" + (nsfw ? "110" : "100"))
            params.push("page=" + page)
        }
        else if (providerId === "zerochan") {
            params.push("c=" + tagString) // zerochan doesn't have search in api, so we use color
            params.push("l=" + limit)
            params.push("s=" + "fav")
            params.push("t=" + 1)
            params.push("p=" + page)
        }
        else if (providerId === "waifu.im") {
            var tagsArray = tagString.split(" ");
            tagsArray.forEach(tag => {
                params.push("included_tags=" + encodeURIComponent(tag));
            });
            params.push("limit=" + Math.min(limit, 30)) // Only admin can do > 30
            params.push("is_nsfw=" + (nsfw ? "null" : "false")) // null is random
        }
        else if (providerId === "t.alcy.cc") {
            url += tagString
            params.push("json")
            params.push("quantity=" + limit)
        }
        else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            if (providerId == "gelbooru") {
                params.push("pid=" + page)
            }
            else {
                params.push("page=" + page)
            }
        }
        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")
        } else {
            url += "&" + params.join("&")
        }
        return url
    }

    // Requests go through curl, not XMLHttpRequest: on some networks a CDN has one blocked address
    // among several, and curl moves on to the next one while Qt keeps waiting on the first.
    // curl also enforces timeouts and can send a User-Agent (Qt drops that header).
    property int requestTimeout: 20 // Seconds, whole request
    property var unreachableProviders: ({})
    property Component requestProcessComponent: Process {
        stdout: StdioCollector {}
    }

    function rememberTags(tags) {
        if (tags.length === 0) return;
        const recent = Persistent.states.booru.recentTags.filter(tag => !tags.includes(tag));
        Persistent.states.booru.recentTags = [...tags, ...recent].slice(0, 30);
    }

    function retry(response) {
        root.responses = root.responses.filter(item => item !== response);
        makeRequest(response.tags, response.nsfw, response.limit, response.page, response.provider);
    }

    function nextPage(response) {
        makeRequest(response.tags, Persistent.states.booru.allowNsfw, response.limit, parseInt(response.page) + 1, response.provider);
    }

    // curlExit: curl's exit code (0 = got an HTTP answer), status: HTTP status
    function describeFailure(providerName, curlExit, status) {
        if (curlExit === 6)
            return Translation.tr("**Can't resolve %1.** Its address may be blocked on your network. Try **Wallhaven**, or use a VPN.").arg(providerName);
        if (curlExit !== 0)
            return Translation.tr("**%1 isn't responding.** It may be blocked on your network. Try **Wallhaven**, or use a VPN.").arg(providerName);
        if (status === 403)
            return Translation.tr("**%1 refused the request (403).** It may be blocking this client or region.").arg(providerName);
        if (status === 429)
            return Translation.tr("**%1 is rate limiting requests.** Wait a moment and retry.").arg(providerName);
        return Translation.tr("**%1 returned an error (HTTP %2).**").arg(providerName).arg(status);
    }

    function userAgentFor(providerId) {
        if (providerId == "zerochan" && Config.options?.sidebar?.booru?.zerochan?.username)
            return `Desktop sidebar booru viewer - username: ${Config.options.sidebar.booru.zerochan.username}`;
        return defaultUserAgent;
    }

    function makeRequest(tags, nsfw=false, limit=20, page=1, providerId=currentProvider) {
        const provider = providers[providerId];
        const url = constructRequestUrl(tags, nsfw, limit, page, providerId);
        rememberTags(tags);

        // Shown immediately as a loading card, filled in when the request finishes
        const newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": providerId,
            "tags": tags,
            "page": page,
            "images": [],
            "message": "",
            "pending": true,
            "nsfw": nsfw,
            "limit": limit,
        });
        root.responses = [...root.responses, newResponse];
        root.runningRequests++;

        const finish = (images, message, failed) => {
            newResponse.images = images;
            newResponse.message = message;
            newResponse.failed = failed;
            newResponse.pending = false;
            root.runningRequests--;
            root.responseFinished();
        };

        console.log(`[Booru] Request to ${url}`);
        const proc = root.requestProcessComponent.createObject(root, {
            "command": ["curl", "--silent", "--location", "--compressed",
                "--connect-timeout", "10", "--max-time", `${root.requestTimeout}`, "--retry", "1",
                "--user-agent", root.userAgentFor(providerId),
                "--write-out", "\n%{http_code}", url],
        });
        proc.exited.connect((exitCode, exitStatus) => {
            const output = proc.stdout.text;
            proc.destroy();
            const lastNewline = output.lastIndexOf("\n");
            const body = lastNewline >= 0 ? output.substring(0, lastNewline) : output;
            const status = parseInt(output.substring(lastNewline + 1)) || 0;

            if (exitCode !== 0 || status !== 200) {
                console.log(`[Booru] Request failed: curl exit ${exitCode}, HTTP ${status}`);
                if (exitCode !== 0) {
                    root.unreachableProviders = Object.assign({}, root.unreachableProviders, { [providerId]: true });
                }
                finish([], root.describeFailure(provider.name, exitCode, status), true);
                return;
            }
            if (root.unreachableProviders[providerId]) {
                const reachable = Object.assign({}, root.unreachableProviders);
                delete reachable[providerId];
                root.unreachableProviders = reachable;
            }
            try {
                const images = provider.manualParseFunc
                    ? provider.manualParseFunc(body)
                    : provider.mapFunc(JSON.parse(body));
                finish(images, images.length > 0 ? "" : root.failMessage, false);
            } catch (e) {
                console.log("[Booru] Failed to parse response: " + e);
                finish([], root.failMessage, false);
            }
        });
        proc.running = true;
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (provider.fixedTags) {
            root.tagSuggestion(query, provider.fixedTags)
            return provider.fixedTags;
        } else if (!provider.tagSearchTemplate) {
            const recentTags = Persistent.states.booru.recentTags
                .filter(tag => tag.startsWith(query.toLowerCase()) && tag !== query)
                .map(tag => ({ "name": tag, "count": Translation.tr("recent") }));
            root.tagSuggestion(query, recentTags);
            return
        }
        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    var response = JSON.parse(xhr.responseText)
                    response = provider.tagMapFunc(response)
                    // console.log("[Booru] Mapped response: " + JSON.stringify(response))
                    root.tagSuggestion(query, response)
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
            }
        }

        try {
            // Required for danbooru
            if (currentProvider == "danbooru") {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        }
    }
}

