#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <math.h>

#define DATA_LENGTH 55       // Número de filas
#define THRESHOLD_BPM 60     // Umbral para BPM bajo
#define WINDOW_SIZE 3        // Tamaño de la ventana para promedio móvil

// Kernel: Normalización
__global__ void normalize(float *data, float *normalized, float min, float max, int length) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < length) {
        normalized[idx] = (data[idx] - min) / (max - min);
    }
}

// Kernel: Promedio móvil
__global__ void movingAverage(float *data, float *smoothed, int length, int window_size) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < length) {
        float sum = 0.0;
        int count = 0;
        for (int j = -window_size / 2; j <= window_size / 2; j++) {
            int neighbor = idx + j;
            if (neighbor >= 0 && neighbor < length) {
                sum += data[neighbor];
                count++;
            }
        }
        smoothed[idx] = sum / count;
    }
}

// Kernel: Detección de cambios bruscos
__global__ void detectAbruptChanges(float *data, bool *abrupt_changes, int length, float threshold) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < length - 1) {
        abrupt_changes[idx] = fabsf(data[idx + 1] - data[idx]) > threshold;
    }
}

// Kernel: Identificación de BPM bajo
__global__ void detectLowBPM(float *bpm, bool *low_bpm, int length, float threshold) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < length) {
        low_bpm[idx] = bpm[idx] < threshold;
    }
}

// Kernel: Clasificación del estado final
__global__ void classifySleep(bool *low_bpm, bool *abrupt_changes, bool *sleep_result, int length) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx < length) {
        sleep_result[idx] = low_bpm[idx] || abrupt_changes[idx];
    }
}

int main() {
    // Variables para almacenar los datos
    float bpm[DATA_LENGTH], accel_y[DATA_LENGTH];

    // Abrir el archivo binario
    FILE *file = fopen("data.bin", "rb");
    if (!file) {
        printf("Error al abrir el archivo data.bin\n");
        return 1;
    }

    // Leer los datos del archivo binario
    size_t read_count = fread(bpm, sizeof(float), DATA_LENGTH, file);
    read_count += fread(accel_y, sizeof(float), DATA_LENGTH, file);
    fclose(file);

    // Verificar si los datos fueron leídos correctamente
    if (read_count != DATA_LENGTH * 2) {
        printf("Error al leer los datos del archivo. Elementos leídos: %lu\n", read_count);
        return 1;
    }

    // Imprimir los datos leídos
    printf("Datos leídos del archivo:\n");
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("Fila %d: BPM=%.2f, Aceleración Y=%.2f\n", i, bpm[i], accel_y[i]);
    }

    // Reservar memoria en GPU
    float *d_bpm, *d_accel_y, *d_normalized, *d_smoothed;
    bool *d_low_bpm, *d_abrupt_changes, *d_sleep_result;
    cudaMalloc((void **)&d_bpm, DATA_LENGTH * sizeof(float));
    cudaMalloc((void **)&d_accel_y, DATA_LENGTH * sizeof(float));
    cudaMalloc((void **)&d_normalized, DATA_LENGTH * sizeof(float));
    cudaMalloc((void **)&d_smoothed, DATA_LENGTH * sizeof(float));
    cudaMalloc((void **)&d_low_bpm, DATA_LENGTH * sizeof(bool));
    cudaMalloc((void **)&d_abrupt_changes, DATA_LENGTH * sizeof(bool));
    cudaMalloc((void **)&d_sleep_result, DATA_LENGTH * sizeof(bool));

    // Copiar datos a GPU
    cudaMemcpy(d_bpm, bpm, DATA_LENGTH * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_accel_y, accel_y, DATA_LENGTH * sizeof(float), cudaMemcpyHostToDevice);

    // Normalizar datos
    float accel_min = -5.0;  // Valor mínimo estimado de aceleración
    float accel_max = 5.0;   // Valor máximo estimado de aceleración
    int threads_per_block = 256;
    int blocks_per_grid = (DATA_LENGTH + threads_per_block - 1) / threads_per_block;
    normalize<<<blocks_per_grid, threads_per_block>>>(d_accel_y, d_normalized, accel_min, accel_max, DATA_LENGTH);

    // Suavizar con promedio móvil
    movingAverage<<<blocks_per_grid, threads_per_block>>>(d_normalized, d_smoothed, DATA_LENGTH, WINDOW_SIZE);

    // Detectar cambios bruscos
    detectAbruptChanges<<<blocks_per_grid, threads_per_block>>>(d_smoothed, d_abrupt_changes, DATA_LENGTH, 0.1);

    // Detectar BPM bajo
    detectLowBPM<<<blocks_per_grid, threads_per_block>>>(d_bpm, d_low_bpm, DATA_LENGTH, THRESHOLD_BPM);

    // Clasificar estado de sueño
    classifySleep<<<blocks_per_grid, threads_per_block>>>(d_low_bpm, d_abrupt_changes, d_sleep_result, DATA_LENGTH);

    // Copiar resultados al host
    bool *low_bpm = (bool *)malloc(DATA_LENGTH * sizeof(bool));
    bool *abrupt_changes = (bool *)malloc(DATA_LENGTH * sizeof(bool));
    bool *sleep_result = (bool *)malloc(DATA_LENGTH * sizeof(bool));
    cudaMemcpy(low_bpm, d_low_bpm, DATA_LENGTH * sizeof(bool), cudaMemcpyDeviceToHost);
    cudaMemcpy(abrupt_changes, d_abrupt_changes, DATA_LENGTH * sizeof(bool), cudaMemcpyDeviceToHost);
    cudaMemcpy(sleep_result, d_sleep_result, DATA_LENGTH * sizeof(bool), cudaMemcpyDeviceToHost);

    // Imprimir resultados
    printf("\nResultados de clasificación de sueño:\n");
    for (int i = 0; i < DATA_LENGTH; i++) {
        printf("Fila %d: BPM=%.2f, Aceleración Y=%.2f, Normalizada=%.2f, BPM Bajo=%s, Cambio Brusco=%s, Resultado Final=%s\n",
       i, bpm[i], accel_y[i], accel_y[i] / accel_max, low_bpm[i] ? "Sí" : "No", abrupt_changes[i] ? "Sí" : "No", sleep_result[i] ? "Dormido" : "Despierto");

    }

    // Liberar memoria
    free(low_bpm);
    free(abrupt_changes);
    free(sleep_result);
    cudaFree(d_bpm);
    cudaFree(d_accel_y);
    cudaFree(d_normalized);
    cudaFree(d_smoothed);
    cudaFree(d_low_bpm);
    cudaFree(d_abrupt_changes);
    cudaFree(d_sleep_result);

    return 0;
}
