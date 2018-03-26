FROM nvidia/cuda:9.1-cudnn7-devel-ubuntu16.04 AS nvidia

FROM kaggle/rcran

COPY --from=nvidia /etc/apt/sources.list.d/cuda.list /etc/apt/sources.list.d/
COPY --from=nvidia /etc/apt/sources.list.d/nvidia-ml.list /etc/apt/sources.list.d/
COPY --from=nvidia /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d/cuda.gpg

# Cuda support.
ENV CUDA_VERSION=9.1.85
ENV CUDA_PKG_VERSION=9-1=$CUDA_VERSION-1
LABEL com.nvidia.volumes.needed="nvidia_driver"
LABEL com.nvidia.cuda.version="${CUDA_VERSION}"
ENV PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
# The stub is useful to us both for built-time linking and run-time linking, on CPU-only systems.
# When intended to be used with actual GPUs, make sure to (besides providing access to the host
# CUDA user libraries, either manually or through the use of nvidia-docker) exclude them. One
# convenient way to do so is to obscure its contents by a bind mount:
#   docker run .... -v /non-existing-directory:/usr/local/cuda/lib64/stubs:ro ...
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/lib64/stubs"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV NVIDIA_REQUIRE_CUDA="cuda>=9.0"
RUN apt-get update && apt-get install -y --no-install-recommends \
      cuda-cudart-$CUDA_PKG_VERSION \
      cuda-libraries-$CUDA_PKG_VERSION \
      cuda-libraries-dev-$CUDA_PKG_VERSION \
      cuda-nvml-dev-$CUDA_PKG_VERSION \
      cuda-minimal-build-$CUDA_PKG_VERSION \
      cuda-command-line-tools-$CUDA_PKG_VERSION \
      libcudnn7=7.0.5.15-1+cuda9.1 \
      libcudnn7-dev=7.0.5.15-1+cuda9.1 && \
    ln -s /usr/local/cuda-9.1 /usr/local/cuda && \
    ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
    rm -rf /var/lib/apt/lists/*


# libv8-dev is needed for package DiagrammR, which xgboost needs

ADD RProfile.R /usr/local/lib/R/etc/Rprofile.site

ADD install_iR.R  /tmp/install_iR.R
ADD bioconductor_installs.R /tmp/bioconductor_installs.R
ADD package_installs.R /tmp/package_installs.R
ADD nbconvert-extensions.tpl /opt/kaggle/nbconvert-extensions.tpl

RUN apt-get update && \
    (echo N; echo N) | apt-get install -y -f r-cran-rgtk2 && \
    apt-get install -y -f libv8-dev libgeos-dev libgdal-dev libproj-dev libsndfile1-dev \
    libtiff5-dev fftw3 fftw3-dev libfftw3-dev libjpeg-dev libhdf4-0-alt libhdf4-alt-dev \
    libhdf5-dev libx11-dev cmake libglu1-mesa-dev libgtk2.0-dev patch && \
    # data.table added here because rcran missed it, and xgboost needs it
    install2.r --error --repo http://cran.rstudio.com \
	DiagrammeR \
	mefa \
	gridSVG \
	rgeos \
	rgdal \
	rARPACK \
	prevR \
	# Rattle installation currently broken by missing "cairoDevice" error
	# rattle \
	Amelia && \
    # XGBoost gets special treatment because the nightlies are hard to build with devtools.
    cd /usr/local/src && git clone --recursive https://github.com/dmlc/xgboost && \
    cd xgboost && make Rbuild && R CMD INSTALL xgboost_*.tar.gz && \
    # Prereq for installing udunits2 package; see https://github.com/edzer/units
    cd /usr/local/src && wget ftp://ftp.unidata.ucar.edu/pub/udunits/udunits-2.2.24.tar.gz && \
    tar zxf udunits-2.2.24.tar.gz && cd udunits-2.2.24 && ./configure && make && make install && \
    ldconfig && echo 'export UDUNITS2_XML_PATH="/usr/local/share/udunits/udunits2.xml"' >> ~/.bashrc && \
    export UDUNITS2_XML_PATH="/usr/local/share/udunits/udunits2.xml" && \
    Rscript /tmp/package_installs.R

RUN Rscript /tmp/bioconductor_installs.R && \
    # This is a work-around to
    # https://stackoverflow.com/questions/49171322/r-object-set-global-graph-attrs-is-not-exported-from-namespacediagrammer
    # TODO(seb): Remove once fixed upstream.
    Rscript -e 'require(devtools) ; install_version("DiagrammeR", version = "0.9.0")' && \
    apt-get update && apt-get install -y libatlas-base-dev libopenblas-dev libopencv-dev && \
    cd /usr/local/src && git clone --recursive --depth=1 --branch 0.11.0 https://github.com/apache/incubator-mxnet.git mxnet && \
    cd mxnet &&  make -j 4 USE_OPENCV=1 USE_BLAS=openblas && \
    cd R-package && Rscript -e "library(devtools); library(methods); options(repos=c(CRAN='https://cran.rstudio.com')); install_deps(dependencies = TRUE)" && \
    cd .. && make rpkg && R CMD INSTALL mxnet_current_r.tar.gz && \
    # Needed for "h5" library
    apt-get install -y libhdf5-dev

RUN apt-get install -y libzmq3-dev && \
    Rscript /tmp/install_iR.R  && \
    cd /usr/local/src && wget https://bootstrap.pypa.io/get-pip.py && \
    python get-pip.py && \
    apt-get install -y python-dev libcurl4-openssl-dev && \
    pip install jupyter pycurl && \
    R -e 'IRkernel::installspec()' && \
    yes | pip uninstall pyzmq && pip install --no-use-wheel pyzmq && \
    cp -r /root/.local/share/jupyter/kernels/ir /usr/local/share/jupyter/kernels && \
# Make sure Jupyter won't try to "migrate" its junk in a read-only container
    mkdir -p /root/.jupyter/kernels && \
    cp -r /root/.local/share/jupyter/kernels/ir /root/.jupyter/kernels && \
    touch /root/.jupyter/jupyter_nbconvert_config.py && touch /root/.jupyter/migrated

# Tensorflow and Keras
# Tensorflow source build
ENV TF_NEED_CUDA=1
ENV TF_CUDA_VERSION=9.1
# Precompile for Tesla k80 and p100.  See https://developer.nvidia.com/cuda-gpus.
ENV TF_CUDA_COMPUTE_CAPABILITIES=3.7,6.0
ENV TF_CUDNN_VERSION=7
ENV KERAS_BACKEND="tensorflow"
RUN apt-get update && \
    apt-get install -y curl gnupg zip && \
    echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu precise main" | tee -a /etc/apt/sources.list && \
    echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu precise main" | tee -a /etc/apt/sources.list && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886 C857C906 2B90D010 && \
    apt-get update && \
    echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections && \
    echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections && \
    apt-get install -y oracle-java8-installer && \
    echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    curl https://bazel.build/bazel-release.pub.gpg | apt-key add - && \
    apt-get update && apt-get install -y bazel && apt-get upgrade -y bazel && \
    pip install numpy --upgrade && \
    cd /usr/local/src && git clone https://github.com/tensorflow/tensorflow && \
    cd tensorflow && cat /dev/null | ./configure && \
    bazel build --config=opt --config=cuda --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" //tensorflow/tools/pip_package:build_pip_package && \
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg && \
    pip install virtualenv && \
    R -e 'keras::install_keras(tensorflow = "'$(ls /tmp/tensorflow_pkg/tensorflow*.whl)'")' && \
    rm -Rf /tmp/tensorflow_pkg
# Py3 handles a read-only environment fine, but Py2.7 needs
# help https://docs.python.org/2/using/cmdline.html#envvar-PYTHONDONTWRITEBYTECODE
ENV PYTHONDONTWRITEBYTECODE=1
# keras::install_keras puts the new libraries inside a virtualenv called r-tensorflow. Importing the
# library triggers a reinstall/rebuild unless the reticulate library gets a strong hint about
# where to find it.
# https://rstudio.github.io/reticulate/articles/versions.html
ENV RETICULATE_PYTHON="/root/.virtualenvs/r-tensorflow/bin/python"

# gpuR.  Do not test loading the libary as that only works on systems GPUs.
RUN R -e 'install.packages("gpuR", INSTALL_opts=c("--no-test-load"))'

# kmcudaR
RUN CPATH=/usr/local/cuda-9.1/targets/x86_64-linux/include install2.r --error --repo http://cran.rstudio.com kmcudaR

# h2o4cuda
RUN install2.r --error --repo http://cran.rstudio.com h2o4gpu

# bayesCL
RUN install2.r --error --repo http://cran.rstudio.com bayesCL

CMD ["R"]
