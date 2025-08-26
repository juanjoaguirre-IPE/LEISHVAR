# ==============================================================================
# Dockerfile para LVAR
# ==============================================================================

# Usar Mambaforge para una instalación de Conda limpia y rápida.
FROM condaforge/mambaforge:latest

LABEL description="Entorno completo para el pipeline LVAR con SnpEff y bcftools."

# Instalar todas las herramientas bioinformáticas necesarias.
RUN mamba install -n base -c conda-forge -c bioconda -y \
    snakemake \
    fastqc \
    multiqc \
    fastp \
    bwa \
    samtools \
    bcftools \
    gatk4 \
    snpeff \
    wget && \
    mamba clean --all -y

# Construir manualmente la base de datos de SnpEff.
RUN \
    # Definir variables
    DB_NAME="Lbraziliensis_custom_db" && \
    FASTA_URL="https://tritrypdb.org/common/downloads/Current_Release/LbraziliensisMHOMBR75M2904/fasta/data/TriTrypDB-68_LbraziliensisMHOMBR75M2904_Genome.fasta" && \
    GFF_URL="https://tritrypdb.org/common/downloads/Current_Release/LbraziliensisMHOMBR75M2904/gff/data/TriTrypDB-68_LbraziliensisMHOMBR75M2904.gff" && \
    GENOME_PATH="/opt/db/genome.fasta" && \
    SNPEFF_CONFIG_FILE=$(find /opt/conda/share -name snpEff.config) && \
    SNPEFF_DATA_DIR=$(dirname "${SNPEFF_CONFIG_FILE}")/data && \
    \
    # Crear directorios
    mkdir -p "${SNPEFF_DATA_DIR}/${DB_NAME}" && \
    mkdir -p /opt/db && \
    \
    # Descargar los archivos de referencia
    wget -O "${SNPEFF_DATA_DIR}/${DB_NAME}/genes.gff" "${GFF_URL}" && \
    wget -O "${GENOME_PATH}" "${FASTA_URL}" && \
    \
    # Preparar archivos para SnpEff
    cp "${GENOME_PATH}" "${SNPEFF_DATA_DIR}/${DB_NAME}/sequences.fa" && \
    \
    # Añadir nuestra base de datos personalizada a la configuración
    echo "" >> "${SNPEFF_CONFIG_FILE}" && \
    echo "# Base de datos manual para L. braziliensis" >> "${SNPEFF_CONFIG_FILE}" && \
    echo "${DB_NAME}.genome : Leishmania braziliensis" >> "${SNPEFF_CONFIG_FILE}" && \
    \
    # Construir la base de datos de SnpEff
    snpEff build -gff3 -v ${DB_NAME} -noCheckCds -noCheckProtein

# Configurar el entorno de trabajo y el punto de entrada para Snakemake.
WORKDIR /pipeline
ENTRYPOINT ["snakemake"]
CMD ["--help"]
