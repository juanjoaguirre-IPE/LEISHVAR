import pandas as pd

# --- Configuracion del Pipeline ---
configfile: "config/config.yaml"
SAMPLES = pd.read_csv(config['samples'], sep='\t').set_index('sample', drop=False)

# Ruta al genoma DENTRO del contenedor (solo lectura)
REF_GENOME_CONTAINER_PATH = "/opt/db/genome.fasta"
# Ruta a copia local de la referencia y sus indices (lectura/escritura)
REF_GENOME_LOCAL = "results/reference/genome.fasta"
# Nombre de la DB de SnpEff que construimos en el Dockerfile
SNPEFF_DB = "Lbraziliensis_custom_db"

# --- Regla Final ---
rule all:
    input:
        "results/comparison/0001.vcf",
        "results/comparison/README.txt"

# --- QC y Trimming ---
rule fastqc:
    input: r1="data/raw_fastq/{sample}_R1.fastq.gz", r2="data/raw_fastq/{sample}_R2.fastq.gz"
    output: zip_r1="results/qc/{sample}_R1_fastqc.zip", zip_r2="results/qc/{sample}_R2_fastqc.zip"
    params: outdir="results/qc"
    log: "results/logs/fastqc/{sample}.log"
    shell: "fastqc {input.r1} {input.r2} -o {params.outdir} --quiet &> {log}"

rule multiqc:
    input: expand("results/qc/{sample}_{read}_fastqc.zip", sample=SAMPLES.index, read=["R1", "R2"])
    output: "results/qc/multiqc_report.html"
    log: "results/logs/multiqc.log"
    shell: "multiqc results/qc -o results/qc -n multiqc_report.html --quiet &> {log}"

rule fastp:
    input: r1="data/raw_fastq/{sample}_R1.fastq.gz", r2="data/raw_fastq/{sample}_R2.fastq.gz"
    output: r1="results/trimmed/{sample}_R1.fastq.gz", r2="results/trimmed/{sample}_R2.fastq.gz"
    log: "results/logs/fastp/{sample}.log"
    threads: 8
    shell: "fastp -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2} --thread {threads} -h /dev/null -j /dev/null &> {log}"

# --- Indexado de Referencia ---
rule copy_reference_for_indexing:
    input: REF_GENOME_CONTAINER_PATH
    output: temp(REF_GENOME_LOCAL)
    shell: "cp {input} {output}"

rule bwa_index:
    input: REF_GENOME_LOCAL
    output: touch(REF_GENOME_LOCAL + ".bwa_indexed")
    log: "results/logs/bwa_index.log"
    shell: "bwa index {input} &> {log}"

rule samtools_faidx:
    input: REF_GENOME_LOCAL
    output: REF_GENOME_LOCAL + ".fai"
    log: "results/logs/samtools_faidx.log"
    shell: "samtools faidx {input} &> {log}"

rule gatk_create_dictionary:
    input: REF_GENOME_LOCAL
    output: REF_GENOME_LOCAL.replace(".fasta", ".dict")
    log: "results/logs/gatk_create_dictionary.log"
    params: java_opts="-Xmx4g"
    shell: "gatk --java-options '{params.java_opts}' CreateSequenceDictionary -R {input} -O {output} &> {log}"

# --- Alineamiento y Post-procesamiento ---
rule bwa_mem_sort:
    input:
        r1="results/trimmed/{sample}_R1.fastq.gz",
        r2="results/trimmed/{sample}_R2.fastq.gz",
        ref=REF_GENOME_LOCAL,
        indexed=REF_GENOME_LOCAL + ".bwa_indexed"
    output: bam="results/aligned/{sample}.sorted.bam"
    params: read_group=r"'@RG\tID:{sample}\tSM:{sample}\tPL:ILLUMINA'"
    log: "results/logs/bwa_mem/{sample}.log"
    threads: 8
    shell: "bwa mem -t {threads} -R {params.read_group} {input.ref} {input.r1} {input.r2} | samtools view -bS - | samtools sort -o {output.bam} &> {log}"

rule mark_duplicates:
    input: "results/aligned/{sample}.sorted.bam"
    output: "results/aligned/{sample}.dedup.bam"
    log: "results/logs/mark_duplicates/{sample}.log"
    params: java_opts="-Xmx8g"
    shell: "gatk --java-options '{params.java_opts}' MarkDuplicates -I {input} -O {output} -M /dev/null &> {log}"

rule samtools_index:
    input: "results/aligned/{sample}.dedup.bam"
    output: "results/aligned/{sample}.dedup.bam.bai"
    log: "results/logs/samtools_index/{sample}.log"
    shell: "samtools index {input} &> {log}"

# --- Llamada de Variantes ---
rule haplotype_caller:
    input:
        bam="results/aligned/{sample}.dedup.bam",
        bai="results/aligned/{sample}.dedup.bam.bai",
        ref=REF_GENOME_LOCAL,
        fai=REF_GENOME_LOCAL + ".fai",
        dict=REF_GENOME_LOCAL.replace(".fasta", ".dict")
    output: vcf="results/variants/{sample}.vcf.gz"
    params: java_opts=f"-Xmx{config.get('gatk_ram_gb', 16)}g"
    log: "results/logs/haplotype_caller/{sample}.log"
    shell: "gatk --java-options '{params.java_opts}' HaplotypeCaller -R {input.ref} -I {input.bam} -O {output.vcf} &> {log}"

# --- Anotacion ---
rule snpeff_annotate:
    input: vcf="results/variants/{sample}.vcf.gz"
    output:
        vcf="results/annotated/{sample}.ann.vcf",
        html="results/annotated/{sample}.snpeff.html"
    params:
        db=SNPEFF_DB,
        java_opts="-Xmx8g"
    log: "results/logs/snpeff/{sample}.log"
    shell:
        """
        export SNPEFF_OPTS="{params.java_opts}"
        snpEff ann -v {params.db} {input.vcf} > {output.vcf} -stats {output.html} 2> {log}
        """

# --- Analisis Comparativo Final ---
rule bgzip_and_tabix:
    input: vcf="results/annotated/{sample}.ann.vcf"
    output:
        gz="results/annotated/{sample}.ann.vcf.gz",
        tbi="results/annotated/{sample}.ann.vcf.gz.tbi"
    log: "results/logs/bgzip_tabix/{sample}.log"
    shell:
        """
        bgzip -c {input.vcf} > {output.gz}
        tabix -p vcf {output.gz}
        """

rule bcftools_isec:
    input:
        vcf1=f"results/annotated/{SAMPLES.index[0]}.ann.vcf.gz",
        tbi1=f"results/annotated/{SAMPLES.index[0]}.ann.vcf.gz.tbi",
        vcf2=f"results/annotated/{SAMPLES.index[1]}.ann.vcf.gz",
        tbi2=f"results/annotated/{SAMPLES.index[1]}.ann.vcf.gz.tbi"
    output:
        unique_to_1="results/comparison/0000.vcf",
        unique_to_2="results/comparison/0001.vcf",
        common_to_both="results/comparison/0002.vcf",
        readme="results/comparison/README.txt"
    params: outdir="results/comparison"
    log: "results/logs/bcftools_isec.log"
    run:
        if len(SAMPLES.index) < 2:
            raise ValueError("La regla 'bcftools_isec' requiere al menos dos muestras.")
        shell("mkdir -p {params.outdir}")
        shell("bcftools isec -p {params.outdir} {input.vcf1} {input.vcf2} &> {log}")
