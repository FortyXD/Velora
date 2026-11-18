//! Wi-Fi backend work is bounded, but time spent asking the user is not backend work.
use crate::protocol::{ApiError, ErrorCode};
use std::{future::Future, time::Duration};
use tokio::{sync::watch, time::Instant};

pub(super) const WORK_TIMEOUT: Duration = Duration::from_secs(60);

pub(super) struct WorkBudget {
    remaining: Duration,
}

impl WorkBudget {
    pub(super) fn new() -> Self { Self { remaining: WORK_TIMEOUT } }

    pub(super) async fn run<T>(&mut self, work: impl Future<Output = Result<T, ApiError>>, mut prompting: watch::Receiver<bool>) -> Result<T, ApiError> {
        tokio::pin!(work);
        loop {
            let paused = *prompting.borrow_and_update();
            let started = Instant::now();
            let result = tokio::select! {
                biased;
                result = &mut work => Some(result),
                changed = prompting.changed() => {
                    if changed.is_err() { return Err(ApiError::new(ErrorCode::Canceled, "The connection was canceled")); }
                    None
                }
                () = tokio::time::sleep(self.remaining), if !paused => Some(Err(ApiError::new(ErrorCode::Timeout, "The connection attempt timed out"))),
            };
            if !paused { self.remaining = self.remaining.saturating_sub(started.elapsed()); }
            if let Some(result) = result { return result; }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test(start_paused = true)]
    async fn backend_work_expires_but_password_wait_does_not() {
        let (prompting, receiver) = watch::channel(false);
        let task = tokio::spawn(async move {
            let mut budget = WorkBudget::new();
            budget.run(std::future::pending::<Result<(), ApiError>>(), receiver).await
        });
        tokio::task::yield_now().await;
        tokio::time::advance(Duration::from_secs(30)).await;
        prompting.send_replace(true);
        tokio::task::yield_now().await;
        tokio::time::advance(Duration::from_secs(600)).await;
        assert!(!task.is_finished(), "user input does not consume the work budget");
        prompting.send_replace(false);
        tokio::task::yield_now().await;
        tokio::time::advance(Duration::from_secs(31)).await;
        assert_eq!(task.await.unwrap().unwrap_err().code, ErrorCode::Timeout);
    }

    #[tokio::test(start_paused = true)]
    async fn separate_stages_share_one_budget() {
        let (_prompting, receiver) = watch::channel(false);
        let mut budget = WorkBudget::new();
        budget.run(async { tokio::time::sleep(Duration::from_secs(40)).await; Ok(()) }, receiver.clone()).await.unwrap();
        assert_eq!(budget.remaining, Duration::from_secs(20));
        let error = budget.run(async { tokio::time::sleep(Duration::from_secs(21)).await; Ok(()) }, receiver).await.unwrap_err();
        assert_eq!(error.code, ErrorCode::Timeout);
    }
}
