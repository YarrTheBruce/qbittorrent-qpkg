#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="qbittorrent"
QPKG_ROOT=$(/sbin/getcfg $QPKG_NAME Install_Path -f $CONF)
export QNAP_QPKG=$QPKG_NAME

BIN="$QPKG_ROOT/qbittorrent-nox"
DATA_DIR="$QPKG_ROOT/data"
PIDFILE="$DATA_DIR/qbittorrent-nox.pid"
LOGFILE="$DATA_DIR/qbittorrent-nox.log"

is_running(){
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

case "$1" in
  start)
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
        echo "$QPKG_NAME is disabled."
        exit 1
    fi

    if [ ! -x "$BIN" ]; then
        echo "$BIN: no such file"
        exit 1
    fi

    if is_running; then
        echo "$QPKG_NAME is already running."
        exit 0
    fi

    /bin/mkdir -p "$DATA_DIR"

    WEBUI_PORT=$(/sbin/getcfg $QPKG_NAME Web_Port -d 6262 -f $CONF)

    # qbittorrent-nox only ever prints its random first-run WebUI password
    # once, before it has written a config file. Detect that case up front
    # so we know whether it's worth polling the log for the password below.
    FIRST_RUN=false
    [ -f "$DATA_DIR/qBittorrent/config/qBittorrent.conf" ] || FIRST_RUN=true

    # NOTE: intentionally not using --daemon; qbittorrent-nox double-forks in
    # that mode, so $! would not track the real running process. Backgrounding
    # it ourselves keeps $! accurate for the stop/status logic above.
    "$BIN" \
        --confirm-legal-notice \
        --webui-port="$WEBUI_PORT" \
        --profile="$DATA_DIR" \
        >>"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"

    # Mirror the first-run temporary WebUI password into the QTS System
    # Event Log too, since App Center gives no other way to see it short of
    # reading $LOGFILE directly over SSH/File Station.
    if [ "$FIRST_RUN" = true ]; then
        for i in $(seq 1 10); do
            /bin/grep -q "temporary password is provided" "$LOGFILE" 2>/dev/null && break
            sleep 1
        done
        TEMP_PASS=$(/bin/sed -n 's/.*temporary password is provided for this session: *//p' "$LOGFILE" | tail -1)
        if [ -n "$TEMP_PASS" ] && [ -x /sbin/log_tool ]; then
            /sbin/log_tool -t0 -uSystem -p127.0.0.1 -mlocalhost -a \
                "qBittorrent WebUI temporary admin password: $TEMP_PASS (port $WEBUI_PORT, user: admin). Log in and change it under WebUI > Options > Web UI."
        fi
    fi
    ;;

  stop)
    if is_running; then
        PID=$(cat "$PIDFILE")
        kill "$PID"
        for i in $(seq 1 30); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID"
    fi
    /bin/rm -f "$PIDFILE"
    ;;

  restart)
    $0 stop
    $0 start
    ;;

  remove)
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|remove}"
    exit 1
esac

exit 0
