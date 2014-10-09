#
# R KWallet Access 0.1
#
# Allows to access KDE's password manager KWallet via DBUS calls.

getKWalletPassword <- function(wallet, folder, key) {

   if(unname(Sys.which("qdbus"))=="") {error("ERROR: getKWalletPassword: qdbus not available!")}
   
   dbus.kwallet.handle <- system(
        paste(
            'qdbus org.kde.kwalletd /modules/kwalletd',
            'open',
            paste('"',wallet,'"',sep=""),
            '0',
            paste('"',R.version.string,'"',sep=""),
            sep=" "
        ),
        intern = TRUE
    )

    dbus.kwallet.password <- system(
        paste(
            'qdbus org.kde.kwalletd /modules/kwalletd', 
            'readPassword',
            dbus.kwallet.handle,
            paste('"',folder,'"',sep=""),
            paste('"',key,'"',sep=""),
            paste('"',R.version.string,'"',sep=""),
            sep=" "
        ),
        intern = TRUE
    )

    dbus.kwallet.disconnected <- "true" == (
        system(
            paste(
                'qdbus org.kde.kwalletd /modules/kwalletd',
                'disconnectApplication',
                paste('"',wallet,'"',sep=""),
                paste('"',R.version.string,'"',sep=""),
                sep=" "
            ),
            intern = TRUE
        )
    )

    dbus.kwallet.closed <- as.integer(
        system(
            paste(
                'qdbus org.kde.kwalletd /modules/kwalletd',
                'close',
                dbus.kwallet.handle,
                'false',
                paste('"',R.version.string,'"',sep=""),
                sep=" "
            ),
            intern = TRUE
        )
    )

    return(dbus.kwallet.password)
}



generateKWalletKey <- function(host, user) {

    kwalletkey <- paste(
        tolower(gsub("[^-.0-9A-Za-z]", "_", host)),
        '__',
        tolower(gsub("[^-.0-9A-Za-z]", "_", user)),
        sep=""
    )
    
    return(kwalletkey)
}
