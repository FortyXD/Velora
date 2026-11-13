# Licensing and third-party notices

Velora is distributed under the **GNU General Public License, version 3**. The
complete text is in [LICENSE](../LICENSE); project attribution and the license
notice for Velora's original contributions are in [NOTICE](../NOTICE).

Velora is derived from [Illogical Impulse](https://github.com/end-4/dots-hyprland).
Its authors retain copyright in their contributions. Existing file-level notices
and license grants remain in effect.

The following components carry their own notices:

| Component | Source / attribution | License and local notice |
| --- | --- | --- |
| Illogical Impulse foundation | end-4 and contributors | GNU GPLv3; [LICENSE](../LICENSE) |
| Fuzzy search | [farzher/fuzzysort](https://github.com/farzher/fuzzysort), Stephen Kamenar | MIT; [MIT.txt](MIT.txt) and the header in `dots/.config/quickshell/ii/modules/common/functions/fuzzysort.js` |
| Lens encrypted database | [SQLCipher](https://github.com/sqlcipher/sqlcipher), Zetetic | BSD-3-Clause; [SQLCipher notice](SQLCipher-BSD-3-Clause.txt) |
| Lens vector search | [USearch](https://github.com/unum-cloud/usearch), Unum | [Apache-2.0](Apache-2.0.txt); dependency pinned in `tools/Cargo.lock` |
| Lens Russian stemming | [rust-stemmers](https://github.com/CurrySoftware/rust-stemmers), Jakob Demler | MIT; [notice](rust-stemmers-MIT.txt) |
| Lens FP16 vector decoding | [half](https://github.com/VoidStarKat/half-rs) | MIT or Apache-2.0; [MIT notice](half-MIT.txt) |
| Lens project exclusions | [ignore / globset](https://github.com/BurntSushi/ripgrep), [bstr](https://github.com/BurntSushi/bstr), [Crossbeam](https://github.com/crossbeam-rs/crossbeam) | MIT option; [dependency notices](lens-ignore-MIT.txt) |
| Lens text model (optional download) | [multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small), Microsoft / intfloat | MIT; source revision recorded in the installed model manifest |
| Lens relevance model (optional download) | [mMARCO multilingual MiniLMv2](https://huggingface.co/cross-encoder/mmarco-mMiniLMv2-L12-H384-v1), Sentence Transformers | Apache-2.0; publisher's ONNX and tokenizer pinned by revision and SHA-256 |
| Lens visual model (optional download) | [SigLIP 2](https://huggingface.co/google/siglip2-base-patch16-224), Google | Apache-2.0; source revision recorded in the installed model manifest |
| Lens inference runtime | [ONNX Runtime](https://github.com/microsoft/onnxruntime), Microsoft | MIT; installed into the optional private Python environment |
| Icon helpers, directory icons and brightness service | [caelestia-dots/shell](https://github.com/caelestia-dots/shell) | GPLv3; notices in `Icons.qml`, `DirectoryIcon.qml` and `Brightness.qml` |
| Levenshtein search helpers | [koeqaife/hyprland-material-you](https://github.com/koeqaife/hyprland-material-you) | GPLv3; notice in `levendist.js` |
| Rounded polygon shapes submodule | [end-4/rounded-polygon-qmljs](https://github.com/end-4/rounded-polygon-qmljs) | Apache-2.0; submodule `LICENSE` |
| Ollama model detection script | strikeoncmputrz/LLM_Scripts | Apache-2.0; `dots/.config/hypr/hyprland/scripts/ai/license_show-loaded-ollama-models.txt` |
| Modified Fluent-style start, search and task view icons | Joshua Oghenekaro Okwe | CC BY 4.0; [asset notice](../dots/.config/quickshell/ii/assets/icons/fluent/README.md) |
| Autumn wallpaper | Josef Bartoň (JoeyJazz) | Artist permission for Velora; **no commercial use of the artwork by third parties**. [Copyright notice](../dots/.config/quickshell/ii/assets/images/autumn.NOTICE.md) |
| Komona Sunset wallpaper | David Revoy | CC BY 4.0; [asset notice](../dots/.config/quickshell/ii/assets/images/komona-sunset.NOTICE.md) and [license](CC-BY-4.0.txt) |
| Mountain wallpaper (dark variant) | Andy Betts; KDE Plasma wallpapers | CC BY-SA 4.0; [asset notice](../dots/.config/quickshell/ii/assets/images/mountain-night.NOTICE.md) and [license](CC-BY-SA-4.0.txt) |

The complete current wallpaper inventory and its distribution terms are recorded
in [Wallpaper sources and distribution terms](wallpapers.md).

[LGPL-3.0.txt](LGPL-3.0.txt) is retained from upstream. Its presence does not
change the license of the project as a whole.

Dependencies installed through pacman, AUR helpers or the Python environment
retain their own licenses. Images downloaded from wallpaper providers remain
subject to the terms attached to each image.

When adding third-party code or assets, preserve their author and license
notices, include any required license text, and update this document.
