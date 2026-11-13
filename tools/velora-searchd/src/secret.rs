use anyhow::{Context, Result};
use futures_util::StreamExt;
use std::collections::HashMap;
use zbus::{Connection, OwnedObjectPath, OwnedVariant, Variant};
use zeroize::Zeroizing;

const BUS: &str = "org.freedesktop.secrets";
const PATH: &str = "/org/freedesktop/secrets";
const SERVICE: &str = "org.freedesktop.Secret.Service";
type Secret = (OwnedObjectPath, Vec<u8>, Vec<u8>, String);

// Only an explicit Settings action may open a system password dialog.
pub async fn request_unlock() -> Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(300), async {
        let conn = Connection::session().await?;
        let service = zbus::Proxy::new(&conn, BUS, PATH, SERVICE).await?;
        let collection: OwnedObjectPath = service.call("ReadAlias", &("default",)).await?;
        let prompt = if collection.as_str() == "/" {
            let props = HashMap::from([(
                "org.freedesktop.Secret.Collection.Label",
                Variant::from("Login"),
            )]);
            let (_, prompt): (OwnedObjectPath, OwnedObjectPath) = service
                .call("CreateCollection", &(props, "default"))
                .await?;
            prompt
        } else {
            let (_, prompt): (Vec<OwnedObjectPath>, OwnedObjectPath) =
                service.call("Unlock", &(vec![collection],)).await?;
            prompt
        };
        if prompt.as_str() != "/" {
            let dialog =
                zbus::Proxy::new(&conn, BUS, prompt.as_str(), "org.freedesktop.Secret.Prompt")
                    .await?;
            let mut completed = dialog.receive_signal("Completed").await?;
            dialog.call::<_, _, ()>("Prompt", &("",)).await?;
            let message = completed
                .next()
                .await
                .context("The keyring dialog closed")?;
            let (dismissed, _): (bool, OwnedVariant) = message.body().deserialize()?;
            anyhow::ensure!(!dismissed, "Keyring unlock cancelled");
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("The keyring dialog timed out")?
}

pub async fn key(create: bool) -> Result<Zeroizing<Vec<u8>>> {
    tokio::time::timeout(std::time::Duration::from_secs(5), obtain(create))
        .await
        .context("Keyring did not respond")?
}

async fn obtain(create: bool) -> Result<Zeroizing<Vec<u8>>> {
    let conn = Connection::session().await?;
    let reply = conn
        .call_method(
            Some(BUS),
            PATH,
            Some(SERVICE),
            "OpenSession",
            &("plain", Variant::from("")),
        )
        .await?;
    let (_, session): (OwnedVariant, OwnedObjectPath) = reply.body().deserialize()?;
    let attrs = HashMap::from([("application", "velora-lens"), ("purpose", "index-key-v1")]);
    let reply = conn
        .call_method(Some(BUS), PATH, Some(SERVICE), "SearchItems", &(&attrs,))
        .await?;
    let (unlocked, locked): (Vec<OwnedObjectPath>, Vec<OwnedObjectPath>) =
        reply.body().deserialize()?;
    let result = if let Some(item) = unlocked.first() {
        let reply = conn
            .call_method(
                Some(BUS),
                item.as_str(),
                Some("org.freedesktop.Secret.Item"),
                "GetSecret",
                &(&session,),
            )
            .await?;
        let (_, _, key, _): Secret = reply.body().deserialize()?;
        anyhow::ensure!(key.len() == 32, "Invalid keyring entry");
        Ok(Zeroizing::new(key))
    } else {
        anyhow::ensure!(
            locked.is_empty(),
            "Unlock the system keyring before using Lens"
        );
        anyhow::ensure!(
            create,
            "Index key is missing; refusing to replace an existing index"
        );
        let collection = "/org/freedesktop/secrets/aliases/default";
        let proxy =
            zbus::Proxy::new(&conn, BUS, collection, "org.freedesktop.Secret.Collection").await?;
        anyhow::ensure!(
            !proxy.get_property::<bool>("Locked").await?,
            "Unlock the system keyring before using Lens"
        );
        let mut key = Zeroizing::new(vec![0; 32]);
        use std::io::Read;
        std::fs::File::open("/dev/urandom")?.read_exact(&mut key)?;
        let props = HashMap::from([
            (
                "org.freedesktop.Secret.Item.Label",
                Variant::from("Velora Lens encrypted index"),
            ),
            (
                "org.freedesktop.Secret.Item.Attributes",
                Variant::from(attrs),
            ),
        ]);
        let secret: Secret = (
            session.clone(),
            vec![],
            key.to_vec(),
            "application/octet-stream".into(),
        );
        let reply = conn
            .call_method(
                Some(BUS),
                collection,
                Some("org.freedesktop.Secret.Collection"),
                "CreateItem",
                &(props, secret, true),
            )
            .await?;
        let (_, prompt): (OwnedObjectPath, OwnedObjectPath) = reply.body().deserialize()?;
        anyhow::ensure!(
            prompt.as_str() == "/",
            "Unlock the system keyring before using Lens"
        );
        Ok(key)
    };
    let _ = conn
        .call_method(
            Some(BUS),
            session.as_str(),
            Some("org.freedesktop.Secret.Session"),
            "Close",
            &(),
        )
        .await;
    result
}
