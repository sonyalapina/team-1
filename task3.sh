#!/bin/bash

input_threshold(){
    local current_usage="$1"
    if [ ! -z "$current_usage" ]; then
        echo "Current usage: $current_usage%"
        echo ""
    fi
    
    while true; do
        read -p "Enter threshold percent (1-100%): " THRESHOLD
        THRESHOLD=$(echo "$THRESHOLD" | xargs)
        
        if [ -z "$THRESHOLD" ]; then
            echo "Threshold cannot be empty"
            continue
        fi
        THRESHOLD=$(echo "$THRESHOLD" | tr -d ' ')
        
        case $THRESHOLD in
            *[!0-9]*)
                echo "Threshold must be a number"
                continue
                ;;
        esac
        
        if [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
            echo "Threshold must be between 1 and 100"
            continue
        fi

        if [ ! -z "$current_usage" ] && [ "$THRESHOLD" -le "$current_usage" ]; then
            echo "WARNING: Threshold ($THRESHOLD%) <= current usage ($current_usage%)"
            read -p "Continue? (y/N): " confirm
            case $confirm in
                [Yy]*) ;;
                *) continue ;;
            esac
        fi

        echo "Threshold set to: $THRESHOLD%"
        echo "$THRESHOLD"
        break
    done
}

input_threshold
