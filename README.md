# LEISHVAR: Pipeline para Análisis de Variantes en Leishmania
[![Snakemake](https://img.shields.io/badge/snakemake-core-brightgreen.svg)](https://snakemake.readthedocs.io)
[![Docker](https://img.shields.io/badge/docker-engine-blue.svg)](https://www.docker.com/)

**LEISHVAR** es un pipeline bioinformático robusto y reproducible para la identificación de variantes genéticas (SNPs/Indels) a partir de datos de secuenciación de genoma completo (WGS) en *Leishmania*. Su objetivo principal es comparar aislados (ej. susceptible vs. resistente a un fármaco) para encontrar las diferencias genéticas clave.

Todo el entorno de software, dependencias y bases de datos están encapsulados en una **única imagen de Docker**, garantizando una ejecución idéntica en cualquier sistema y eliminando la necesidad de instalaciones manuales.

---

## Flujo de Trabajo del Pipeline

El análisis se realiza en 6 pasos principales, orquestados por Snakemake:

1.  **Control de Calidad (QC)**: `FastQC` y `MultiQC`.
2.  **Limpieza de Lecturas (Trimming)**: `fastp`.
3.  **Alineamiento**: `BWA-MEM`.
4.  **Post-procesamiento**: `GATK MarkDuplicates` y `Samtools`.
5.  **Llamada de Variantes**: `GATK HaplotypeCaller`.
6.  **Anotación y Comparación**: `SnpEff` y `bcftools`.

---

## Guía de Uso Rápido

### Requisitos Previos
-   **Git**
-   **Docker** (asegúrate de que el servicio esté activo).

### Fase 1: Instalación y Configuración (Solo se hace una vez)

1.  **Clonar el Repositorio**
    Abre una terminal, clona el proyecto y entra en el directorio.
    ```bash
    git clone https://github.com/juanjoaguirre-IPE/LEISHVAR.git
    cd LEISHVAR
    ```

2.  **Ejecutar el Script de Configuración**
    Este asistente interactivo preparará todo el proyecto.
    ```bash
    chmod +x setup.sh
    ./setup.sh
    ```
    El script te guiará para:
    *   **Validar URLs** para el genoma y la anotación (puedes proporcionar las tuyas o usar las sugeridas).
    *   **Construir la imagen de Docker** (puede tardar más de 30 minutos la primera vez).
    *   **Definir tus muestras** (ej. `susceptible` y `resistente`).
    *   **Asignar recursos** (cores y RAM).
    *   **Copiar tus archivos FASTQ**.

    Al finalizar, se crearán dos scripts esenciales: `run_pipeline.sh` y `run_in_container.sh`.

### Fase 2: Ejecución del Análisis

1.  **Iniciar el Pipeline Completo**
    Este comando ejecutará todos los pasos, desde el QC hasta la comparación de variantes.
    ```bash
    ./run_pipeline.sh
    ```

2.  **(Opcional) Realizar una Simulación (Dry-run)**
    Para ver el plan de ejecución sin correr los trabajos, usa el flag `-n`.
    ```bash
    ./run_pipeline.sh -n
    ```

### Fase 3: Interpretación de Resultados

Una vez que el pipeline termine, tus resultados estarán listos.

1.  **Encontrar los Resultados Clave**
    El archivo más importante es **`results/comparison/0001.vcf`**. Contiene las variantes que son **exclusivas del segundo aislado** que definiste (ej. el resistente).

2.  **Visualizar con IGV (Recomendado)**

    a. **Extraer los archivos de referencia del contenedor:**
    ```bash
    # Extraer el genoma FASTA
    ./run_in_container.sh cat /opt/db/genome.fasta > leishmania_genome.fasta

    # Extraer la anotación GFF
    ./run_in_container.sh cat /opt/conda/share/snpeff-5.2-1/data/Lbraziliensis_custom_db/genes.gff > leishmania_annotation.gff
    ```

    b. **Cargar en IGV (en tu PC local):**
    *   Abre IGV.
    *   Carga el genoma: `Genomes` -> `Load Genome from File...` -> `leishmania_genome.fasta`.
    *   Carga la anotación: `File` -> `Load from File...` -> `leishmania_annotation.gff`.
    *   Carga tus variantes candidatas: `File` -> `Load from File...` -> `results/comparison/0001.vcf`.

    c. **Investigar Genes de Interés:**
    Usa la barra de búsqueda de IGV para saltar a genes específicos (ej. `LbrM.31.0020` para AQP1) y ver si tienen mutaciones en la pista de tu VCF.

3.  **Explorar con la Línea de Comandos**
    Puedes usar el script `run_in_container.sh` para filtrar tus resultados.

    ```bash
    # Ver el contenido del archivo de variantes únicas
    ./run_in_container.sh less results/comparison/0001.vcf

    # Filtrar para encontrar solo mutaciones de ALTO impacto
    ./run_in_container.sh grep 'HIGH' results/comparison/0001.vcf
    ```

---

## Estructura del Repositorio
```
LEISHVAR/
├── Dockerfile # Imagen de Docker.
├── Snakefile # Lógica del pipeline.
├── setup.sh # Script de configuración.
├── .gitignore # Archivos y carpetas a ignorar por Git.
└── README.md # Este archivo.
```
*Las carpetas `config/`, `data/` y `results/` son creadas localmente por el script `setup.sh`.*
