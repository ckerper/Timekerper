export function useOutlookStub() {
  return {
    outlookAvailable: false,
    outlookConnected: false,
    outlookStatus: 'idle',
    outlookError: null,
    lastFetched: null,
    connectOutlook: () => {},
    disconnectOutlook: () => {},
    refreshOutlookEvents: () => {},
    pendingOutlookImport: null,
    finishOutlookImport: () => {},
    pendingOutlookReplace: null,
    finishOutlookReplace: () => {},
  }
}
