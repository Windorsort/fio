#!/bin/bash

# Настройки по умолчанию
VSTORAGE_PATH="/mnt/vstorage/vols/datastores/cinder/test"
RESULTS_DIR="/root/fio_testing_vstorage2"
LOG_FILE="${RESULTS_DIR}/test_log_$(date +%Y%m%d_%H%M%S).log"
ITERATIONS=${ITERATIONS:-3}  # Количество итераций
RWMIXREAD_VALUES=(70 30)    # Значения rwmixread
SIZE=${SIZE:-500M}          # Объём данных для теста
TIMEOUT=900                 # Тайм-аут 30 минут
NUMJOBS=$(expr 4 \* $(grep -c ^processor /proc/cpuinfo))                 # Количество параллельных задач

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Настройка vstorage
log "Настройка параметров vstorage..."
vstorage -c Cluster2U set-attr -R "$VSTORAGE_PATH" tier=0 replicas=3:2 || {
    log "Ошибка: Не удалось установить атрибуты vstorage."
    exit 1
}

# Создание и проверка директорий
log "Проверка и создание директорий..."
mkdir -p "$VSTORAGE_PATH" "$RESULTS_DIR"
chmod 755 "$VSTORAGE_PATH" "$RESULTS_DIR" || {
    log "Ошибка: Не удалось установить права на директории."
    exit 1
}

if [ ! -d "$VSTORAGE_PATH" ]; then
    log "Ошибка: Директория $VSTORAGE_PATH не существует."
    exit 1
fi
cd "$VSTORAGE_PATH" || {
    log "Ошибка: Не удалось перейти в директорию $VSTORAGE_PATH."
    exit 1
}

# Проверка наличия утилиты vstorage
if ! command -v vstorage &> /dev/null; then
    log "Ошибка: Утилита vstorage не установлена."
    exit 1
fi
vstorage get-attr "$VSTORAGE_PATH" || {
    log "Ошибка при выполнении vstorage get-attr."
    exit 1
}

# Проверка наличия утилиты fio
if ! command -v fio &> /dev/null; then
    log "Ошибка: Утилита fio не установлена."
    exit 1
fi

# Функция для выполнения теста и обработки результатов
run_test() {
    local rwmixread=$1
    local iteration=$2
    local output_file="${RESULTS_DIR}/results_rwmixread_${rwmixread}_iteration_${iteration}.txt"
    local temp_file="${RESULTS_DIR}/temp_${rwmixread}_${iteration}.txt"

    log "Сохранение старых результатов в ${temp_file}..."
    [ -f "$output_file" ] && mv "$output_file" "$temp_file"

    log "Удаление всех файлов в текущей директории $VSTORAGE_PATH..."
    rm -rf ./* 2>> "$LOG_FILE" || {
        log "Ошибка при удалении файлов."
        exit 1
    }

    log "Запуск теста с rwmixread=${rwmixread}, итерация ${iteration} с объёмом $SIZE..."
    if ! timeout "$TIMEOUT" fio --name=randrw --rw=randrw --direct=1 --ioengine=libaio --bs=4k --numjobs=$NUMJOBS --size="$SIZE" --time_based=0 --rwmixread="$rwmixread" --group_reporting --output="$output_file" 2>> "$LOG_FILE"; then
        log "Ошибка: Тест fio с rwmixread=${rwmixread}, итерация ${iteration} завершился с ошибкой или превысил время (${TIMEOUT} сек)."
        exit 1
    fi

    if [ ! -s "$output_file" ]; then
        log "Ошибка: Файл результатов $output_file пуст."
        exit 1
    fi
    log "Тест завершен, результаты в $output_file"
}

# Последовательное выполнение тестов
log "Запуск тестов..."
for iteration in $(seq 1 "$ITERATIONS"); do
    for rwmixread in "${RWMIXREAD_VALUES[@]}"; do
        run_test "$rwmixread" "$iteration"
    done
done

log "Все тесты завершены."
