const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('electronOutlook', {
  isElectron: true,
  checkAccount: () => ipcRenderer.invoke('outlook:check-account'),
  connect: () => ipcRenderer.invoke('outlook:connect'),
  fetchEvents: (startDate, endDate) => ipcRenderer.invoke('outlook:fetch-events', startDate, endDate),
  disconnect: () => ipcRenderer.invoke('outlook:disconnect'),
})
