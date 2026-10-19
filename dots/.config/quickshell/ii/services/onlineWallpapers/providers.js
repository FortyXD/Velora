.pragma library

/*
 * Online wallpaper sources. Each provider turns a search into an HTTP request and the response
 * into items of one shape:
 *   { id, width, height, thumb, full, fileExt, pageUrl, title, author, license, lowRes, downloadPing }
 * ctx: { query, page, sorting, category, fitScreen, screenWidth, screenHeight, color, key, state, subreddits }
 * `state` survives between pages of one search (for cursor-style paging).
 */

function enc(value) {
    return encodeURIComponent(value);
}

function extOf(url, fallback) {
    const match = (url || "").split("?")[0].match(/\.(jpe?g|png|webp|gif)$/i);
    return match ? match[1].toLowerCase().replace("jpeg", "jpg") : (fallback || "jpg");
}

function ratioString(ctx) {
    // Wallhaven's ratio names, for the screen's shape
    const r = ctx.screenWidth / ctx.screenHeight;
    if (Math.abs(r - 16 / 10) < 0.03) return "16x10";
    if (Math.abs(r - 21 / 9) < 0.06) return "21x9";
    if (Math.abs(r - 32 / 9) < 0.08) return "32x9";
    if (Math.abs(r - 4 / 3) < 0.03) return "4x3";
    return "16x9";
}

function stripHtml(text) {
    return (text || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();
}

const providers = [
    {
        id: "wallhaven",
        name: "Wallhaven",
        icon: "landscape",
        homepage: "https://wallhaven.cc",
        description: "General, anime and people wallpapers in high resolution",
        needsKey: false,
        keyOptional: true,
        supportsQuery: true,
        sortings: ["relevance", "toplist", "random", "date_added", "views", "favorites"],
        categories: ["all", "general", "anime", "people"],
        supportsColor: true,
        request: function(ctx) {
            const categories = { all: "111", general: "100", anime: "010", people: "001" }[ctx.category || "all"] || "111";
            let sorting = ctx.sorting || (ctx.query ? "relevance" : "toplist");
            let params = [
                "categories=" + categories,
                "purity=100",
                "sorting=" + sorting,
                "page=" + ctx.page,
            ];
            if (ctx.query) params.push("q=" + enc(ctx.query));
            if (sorting === "toplist") params.push("topRange=1M");
            if (ctx.fitScreen) {
                params.push("atleast=" + ctx.screenWidth + "x" + ctx.screenHeight);
                params.push("ratios=" + ratioString(ctx));
            }
            if (ctx.color) params.push("colors=" + ctx.color.replace("#", ""));
            if (ctx.key) params.push("apikey=" + enc(ctx.key));
            return { url: "https://wallhaven.cc/api/v1/search?" + params.join("&"), headers: [] };
        },
        parse: function(text) {
            const json = JSON.parse(text);
            return {
                items: (json.data || []).map(function(item) {
                    return {
                        id: item.id, width: item.dimension_x, height: item.dimension_y,
                        thumb: item.thumbs.small, full: item.path, fileExt: extOf(item.path),
                        pageUrl: item.url, title: item.resolution, author: "", license: "Wallhaven"
                    };
                }),
                hasMore: json.meta ? json.meta.current_page < json.meta.last_page : false
            };
        }
    },
    {
        id: "unsplash",
        name: "Unsplash",
        icon: "photo_camera",
        homepage: "https://unsplash.com/developers",
        description: "Free high-quality photos; needs a free access key",
        needsKey: true,
        supportsQuery: true,
        sortings: ["relevant", "latest"],
        request: function(ctx) {
            const headers = ["Authorization: Client-ID " + ctx.key, "Accept-Version: v1"];
            if (ctx.query) {
                return {
                    url: "https://api.unsplash.com/search/photos?per_page=30&orientation=landscape&page=" + ctx.page
                        + "&order_by=" + (ctx.sorting || "relevant") + "&query=" + enc(ctx.query),
                    headers: headers
                };
            }
            return { url: "https://api.unsplash.com/photos?per_page=30&order_by=popular&page=" + ctx.page, headers: headers };
        },
        parse: function(text, ctx) {
            const json = JSON.parse(text);
            const list = Array.isArray(json) ? json : (json.results || []);
            return {
                items: list.map(function(item) {
                    return {
                        id: item.id, width: item.width, height: item.height,
                        thumb: item.urls.small, full: item.urls.raw + "&w=" + Math.max(ctx.screenWidth, 1920) + "&fm=jpg&q=90",
                        fileExt: "jpg", pageUrl: item.links.html, title: item.alt_description || "",
                        author: item.user ? item.user.name : "", license: "Unsplash License",
                        downloadPing: item.links.download_location // Required by the Unsplash API when downloading
                    };
                }),
                hasMore: Array.isArray(json) ? list.length > 0 : ctx.page < (json.total_pages || 0)
            };
        }
    },
    {
        id: "pexels",
        name: "Pexels",
        icon: "camera",
        homepage: "https://www.pexels.com/api/",
        description: "Free stock photos; needs a free API key",
        needsKey: true,
        supportsQuery: true,
        request: function(ctx) {
            const headers = ["Authorization: " + ctx.key];
            if (ctx.query) {
                return {
                    url: "https://api.pexels.com/v1/search?per_page=40&orientation=landscape&size=large&page=" + ctx.page + "&query=" + enc(ctx.query),
                    headers: headers
                };
            }
            return { url: "https://api.pexels.com/v1/curated?per_page=40&page=" + ctx.page, headers: headers };
        },
        parse: function(text) {
            const json = JSON.parse(text);
            return {
                items: (json.photos || []).map(function(item) {
                    return {
                        id: String(item.id), width: item.width, height: item.height,
                        thumb: item.src.medium, full: item.src.original, fileExt: extOf(item.src.original),
                        pageUrl: item.url, title: item.alt || "", author: item.photographer || "", license: "Pexels License"
                    };
                }),
                hasMore: !!json.next_page
            };
        }
    },
    {
        id: "pixabay",
        name: "Pixabay",
        icon: "filter_hdr",
        homepage: "https://pixabay.com/api/docs/",
        description: "Free images; needs a free API key. Without full API access images are at most 1280 px",
        needsKey: true,
        supportsQuery: true,
        sortings: ["popular", "latest"],
        categories: ["all", "backgrounds", "nature", "places", "science", "travel", "buildings"],
        request: function(ctx) {
            let params = [
                "key=" + enc(ctx.key), "image_type=photo", "orientation=horizontal", "safesearch=true",
                "per_page=40", "page=" + ctx.page, "order=" + (ctx.sorting || "popular")
            ];
            if (ctx.query) params.push("q=" + enc(ctx.query));
            if (ctx.category && ctx.category !== "all") params.push("category=" + ctx.category);
            if (ctx.fitScreen) params.push("min_width=" + ctx.screenWidth);
            return { url: "https://pixabay.com/api/?" + params.join("&"), headers: [] };
        },
        parse: function(text, ctx) {
            const json = JSON.parse(text);
            return {
                items: (json.hits || []).map(function(item) {
                    const full = item.imageURL || item.fullHDURL || item.largeImageURL;
                    return {
                        id: String(item.id), width: item.imageWidth, height: item.imageHeight,
                        thumb: item.webformatURL, full: full, fileExt: extOf(full),
                        pageUrl: item.pageURL, title: item.tags || "", author: item.user || "", license: "Pixabay License",
                        lowRes: !item.imageURL && !item.fullHDURL
                    };
                }),
                hasMore: ctx.page * 40 < (json.totalHits || 0)
            };
        }
    },
    {
        id: "bing",
        name: "Bing",
        icon: "today",
        homepage: "https://www.bing.com",
        description: "Photos of the day from the last week",
        needsKey: false,
        supportsQuery: false,
        request: function(ctx) {
            return { url: "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=ru-RU", headers: [] };
        },
        parse: function(text) {
            const json = JSON.parse(text);
            return {
                items: (json.images || []).map(function(item) {
                    const base = "https://www.bing.com" + item.urlbase;
                    return {
                        id: item.startdate + "-" + (item.hsh || "").slice(0, 8), width: 3840, height: 2160,
                        thumb: base + "_400x240.jpg", full: base + "_UHD.jpg", fileExt: "jpg",
                        pageUrl: item.copyrightlink || "https://www.bing.com", title: item.title || "",
                        author: item.copyright || "", license: "Bing"
                    };
                }),
                hasMore: false
            };
        }
    },
    {
        id: "nasa",
        name: "NASA APOD",
        icon: "rocket_launch",
        homepage: "https://api.nasa.gov",
        description: "Astronomy pictures of the day, at random. Works without a key with tight limits",
        needsKey: false,
        keyOptional: true,
        supportsQuery: false,
        request: function(ctx) {
            return { url: "https://api.nasa.gov/planetary/apod?count=24&thumbs=true&api_key=" + enc(ctx.key || "DEMO_KEY"), headers: [] };
        },
        parse: function(text) {
            const json = JSON.parse(text);
            return {
                items: (Array.isArray(json) ? json : [json]).filter(function(item) {
                    return item.media_type === "image";
                }).map(function(item) {
                    const full = item.hdurl || item.url;
                    return {
                        id: item.date, width: 0, height: 0, thumb: item.url, full: full, fileExt: extOf(full),
                        pageUrl: "https://apod.nasa.gov/apod/ap" + item.date.replace(/-/g, "").slice(2) + ".html",
                        title: item.title || "", author: item.copyright ? item.copyright.trim() : "NASA", license: "NASA APOD"
                    };
                }),
                hasMore: true
            };
        }
    },
    {
        id: "wikimedia",
        name: "Wikimedia Commons",
        icon: "account_balance",
        homepage: "https://commons.wikimedia.org",
        description: "Featured pictures with free licenses",
        needsKey: false,
        supportsQuery: true,
        request: function(ctx) {
            const search = (ctx.query ? ctx.query + " " : "") + "incategory:Featured_pictures_on_Wikimedia_Commons filetype:bitmap";
            const params = [
                "action=query", "format=json", "origin=*", "generator=search", "gsrnamespace=6",
                "gsrlimit=30", "gsroffset=" + (ctx.page - 1) * 30, "gsrsearch=" + enc(search),
                "prop=imageinfo", "iiprop=url|size|extmetadata", "iiurlwidth=480"
            ];
            return { url: "https://commons.wikimedia.org/w/api.php?" + params.join("&"), headers: [] };
        },
        parse: function(text) {
            const json = JSON.parse(text);
            const pages = json.query ? Object.values(json.query.pages) : [];
            pages.sort(function(a, b) { return (a.index || 0) - (b.index || 0); });
            return {
                items: pages.filter(function(page) {
                    const info = page.imageinfo && page.imageinfo[0];
                    return info && info.width >= info.height; // Wallpapers are landscape
                }).map(function(page) {
                    const info = page.imageinfo[0];
                    const meta = info.extmetadata || {};
                    return {
                        id: String(page.pageid), width: info.width, height: info.height,
                        thumb: info.thumburl, full: info.url, fileExt: extOf(info.url),
                        pageUrl: info.descriptionurl, title: (page.title || "").replace(/^File:/, "").replace(/\.[^.]+$/, ""),
                        author: stripHtml(meta.Artist ? meta.Artist.value : ""),
                        license: meta.LicenseShortName ? meta.LicenseShortName.value : ""
                    };
                }),
                hasMore: !!json["continue"]
            };
        }
    },
    {
        id: "reddit",
        name: "Reddit",
        icon: "forum",
        homepage: "https://www.reddit.com",
        description: "Top posts of wallpaper subreddits. Reddit often refuses requests without signing in",
        needsKey: false,
        supportsQuery: true,
        sortings: ["week", "month", "year", "all"],
        request: function(ctx) {
            const subs = (ctx.subreddits || "wallpaper+wallpapers+EarthPorn").replace(/\s*,\s*|\s+/g, "+");
            const after = ctx.state && ctx.state.after ? "&after=" + ctx.state.after : "";
            const time = ctx.sorting || "month";
            const url = ctx.query
                ? "https://www.reddit.com/r/" + subs + "/search.json?restrict_sr=1&sort=top&limit=50&raw_json=1&t=" + time + "&q=" + enc(ctx.query) + after
                : "https://www.reddit.com/r/" + subs + "/top.json?limit=50&raw_json=1&t=" + time + after;
            return { url: url, headers: [] };
        },
        parse: function(text, ctx) {
            const json = JSON.parse(text);
            const data = json.data || {};
            ctx.state.after = data.after || "";
            return {
                items: (data.children || []).map(function(child) { return child.data; }).filter(function(post) {
                    return !post.over_18 && post.preview && post.preview.images && /\.(jpe?g|png|webp)$/i.test(post.url || "");
                }).map(function(post) {
                    const image = post.preview.images[0];
                    const small = image.resolutions[Math.min(2, image.resolutions.length - 1)] || image.source;
                    return {
                        id: post.id, width: image.source.width, height: image.source.height,
                        thumb: small.url, full: post.url, fileExt: extOf(post.url),
                        pageUrl: "https://www.reddit.com" + post.permalink, title: post.title || "",
                        author: "u/" + post.author, license: "r/" + post.subreddit
                    };
                }),
                hasMore: !!data.after
            };
        }
    },
    {
        id: "openverse",
        name: "Openverse",
        icon: "copyright",
        homepage: "https://openverse.org",
        description: "Openly licensed images from many collections. Anonymous use is limited to 200 requests a day",
        needsKey: false,
        supportsQuery: true,
        request: function(ctx) {
            const params = ["aspect_ratio=wide", "size=large", "page_size=20", "page=" + ctx.page, "q=" + enc(ctx.query || "landscape")];
            return { url: "https://api.openverse.org/v1/images/?" + params.join("&"), headers: [] };
        },
        parse: function(text, ctx) {
            const json = JSON.parse(text);
            return {
                items: (json.results || []).map(function(item) {
                    return {
                        id: item.id, width: item.width || 0, height: item.height || 0,
                        thumb: item.thumbnail, full: item.url, fileExt: extOf(item.url),
                        pageUrl: item.foreign_landing_url, title: item.title || "", author: item.creator || "",
                        license: ((item.license || "") + " " + (item.license_version || "")).trim().toUpperCase()
                    };
                }),
                hasMore: ctx.page < (json.page_count || 0)
            };
        }
    },
];

function find(id) {
    for (let i = 0; i < providers.length; i++) {
        if (providers[i].id === id) return providers[i];
    }
    return null;
}
