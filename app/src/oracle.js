import Web3 from "web3";
import recyclerArtifact from "../../build/CustomOracle.json";

const App = {
  web3: null,
  account: null,
  meta: null,
  eventSet: null,
  owner: null,
  paused: false,
  isAdmin: false,
  valuesPerPack: null,
  otherValues: null,
  priceEthMin: 0,
  priceEthMax: 0,

  DEC_POS_DIV: 10000,

  //*
  //*   start: Función inicial
  //*
  start: async function() {

      const { web3 } = this;

      console.info("App.start");

      try {
          // get contract instance
          const networkId = await web3.eth.net.getId();
          console.log("networkId: ", networkId);          
          const deployedNetwork = recyclerArtifact.networks[networkId];
          this.meta = new web3.eth.Contract(
              recyclerArtifact.abi,
              deployedNetwork.address,
          );

          // Obtiene la cuenta con que se va a trabajar
          const accounts = await web3.eth.getAccounts();
          this.account = accounts[0];

          //Debug
          console.log("Esta cuenta: ", this.account);

          this.eventSet = new Set();

          this.valuesPerPack = [[], [], []];
          this.otherValues = [ 0, 0, 0, 0, 0];

          //Debug
          console.log("Informa los detalles: ", this.account, "/", networkId);

          document.getElementById("cuenta").innerHTML = this.account;
          document.getElementById("red").innerHTML = networkId;
          document.getElementById("contractAddress").innerHTML = deployedNetwork.address;

          await this.getIsAdmin();

          //Debug
          console.log("IsAdmin: ", this.isAdmin);

          document.getElementById("updateButton1").disabled = !this.isAdmin;
          document.getElementById("updateButton2").disabled = !this.isAdmin;
          document.getElementById("updateButton3").disabled = !this.isAdmin;
          document.getElementById("pauseButton").disabled = !this.isAdmin;
          document.getElementById("checkButton").disabled = !this.isAdmin;
          document.getElementById("add-admin").disabled = !this.isAdmin;

          await this.getIsPaused();
          
          // Inicializa campos UI con los valores actuales
          this.loadValues();
          this.setEvents();

          document.getElementById("address-admin").value = "";
          document.getElementById("points-min1").focus();

      } catch (error) {
          console.error("Could not connect to contract or chain.");
          this.setStatus("Could not connect to contract or chain.");

          //Debug
          console.log("Error: ", error);
      }
  },

  //*
  //* loadValues: Inicializa campos de pantalla a partir de los valores actuales
  //*             disponibles en el SC.
  //*
  loadValues: async function() {

    //DEBUG 
    console.log("**loadValues**");

    this.getValuesPerPack();
    this.getEthValues();
    this.getOtherValues();
    this.getStatusValues();
    showMessage("Información actualizada");

    //DEBUG 
    console.log("**loadValues fin**");

  },

  //*
  //* setEvents: Define el comportamiento de la aplicación antes los eventos que reciba del SC
  //*
  //* Las variables de tipo set (eventSet, 2, 3..) almacenan los hashes de las transacciones procesadas. Dado que
  //* un mismo evento puede recibirse varias veces para una misma transacción, se guarda el hash para tratar el evento
  //* una única vez.
  //*
  setEvents: async function() {

    //* 
    //* Tratamiento evento packagingFullUpdate
    //*
    let eventpackagingFullUpdate = this.meta.events.packagingFullUpdate({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("packagingFullUpdate hash: ", event.transactionHash);

            if (!this.eventSet.has(event.transactionHash)) {

                this.eventSet.add(event.transactionHash);

                showMessage("Evento packagingFullUpdate recibido");
                alert("Operación completada.\n\n"+ "Tx hash:\n" + event.transactionHash);
            }
        }      
    }.bind(this));

    //* 
    //* Tratamiento evento otherValuesFullUpdate
    //*
    let eventNewBalance = this.meta.events.otherValuesFullUpdate({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("otherValuesFullUpdate hash: ", event.transactionHash);

            if (!this.eventSet.has(event.transactionHash)) {

                this.eventSet.add(event.transactionHash);

                showMessage("Evento otherValuesFullUpdate recibido");
                alert("Operación completada.\n\n"+ "Tx hash:\n" + event.transactionHash);
            }
        }      
    }.bind(this));   

    //* 
    //* Tratamiento evento ethPriceUpdate
    //*
    let eventethPriceUpdate = this.meta.events.ethPriceUpdate({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("ethPriceUpdate hash: ", event.transactionHash);

            if (!this.eventSet.has(event.transactionHash)) {

                this.eventSet.add(event.transactionHash);
                showMessage("Evento ethPriceUpdate recibido");
                alert("Operación completada.\n\n"+ "Tx hash:\n" + event.transactionHash);
            }
        }      
    }.bind(this));  
    
    //* 
    //* Tratamiento evento newPointsReward
    //*
    let eventNewPointsReward = this.meta.events.newPointsReward({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("newPointsReward hash: ", event.transactionHash);

            if (!this.eventSet.has(event.transactionHash)) {

                this.eventSet.add(event.transactionHash);
                this.loadValues();
                showMessage("Evento newPointsReward recibido");
                alert("Actualización completada.\n\n"+ "Tx hash:\n" + event.transactionHash);
            }
        }      
    }.bind(this));  
    
    //* 
    //* Tratamiento evento LogNewProvableQuery
    //*
    let eventLogNewProvableQuery = this.meta.events.LogNewProvableQuery({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("LogNewProvableQuery hash: ", event.transactionHash);

            if (!this.eventSet.has(event.transactionHash)) {

                this.eventSet.add(event.transactionHash);
                showMessage("Evento LogNewProvableQuery. " + event.returnValues.description);
            }
        }      
    }.bind(this)); 

    //* 
    //* Tratamiento evento Paused
    //*
    let eventPause = this.meta.events.Paused({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("Paused hash: ", event.transactionHash);
    
            if (!this.eventSet.has(event.transactionHash)) {
    
                this.eventSet.add(event.transactionHash);

                alert("El contrato ha sido pausado correctamente\n"+ "Tx hash:\n" + event.transactionHash);
                this.setStatus("Contrato pausado");
                this.getIsPaused();
            }
        }

    }.bind(this));

    //* 
    //* Tratamiento evento Unpaused
    //*
    let eventUnpause = this.meta.events.Unpaused({ filter: {_sender: this.address}}, function(error, event){ 

        if (!error) {

            console.info("Unpaused hash: ", event.transactionHash);
    
            if (!this.eventSet.has(event.transactionHash)) {
    
                this.eventSet.add(event.transactionHash);

                alert("EL contrato ha sido despausado correctamente\n"+ "Tx hash:\n" + event.transactionHash);
                this.setStatus("Contrato despausado");
                this.getIsPaused();
            }
        }

    }.bind(this));

  },

  //*
  //* addAdmin: Cambia el estado de una cuenta a Admin, con lo que adquiere todos los
  //* permisos correspondientes.
  //*
  addAdmin: async function() {

    //DEBUG
    console.log("**addAdmin**");

    if (this.paused) {
        showMessage("Error. El contrato está en pausa");
        alert("Error.\n No se puede actualizar\n El contrato está en pausa");
    } else {

        const addressAdmin = document.getElementById("address-admin");

        // Se verifica que el valor del campo de input sea válido
        if (addressAdmin.checkValidity()) {

            const { addAdmin } = this.meta.methods;

            await addAdmin(addressAdmin.value).send({
                  from: this.account
                }, function (error, transactionHash) {
                    if (error) {
                      console.error("Error addAdmin: ", error);
                      showMessage("Error. Transacción no completada");
                      alert("Error. Transacción no completada.");
                    } else {
                      console.info("Transaction hash: ", transactionHash);
                      showMessage("Actualización realizada. Espere confirmación.");
                      alert("Solicitud enviada correctamente\n" + "Tx hash:\n" + transactionHash);
                    }
                });

            addressAdmin.value = "";

        } else {
            this.setStatus("ERROR. Dato de entrada no válido.");
            alert("ERROR. Dato de entrada no válido.");
        }
    }
  },

  //*
  //*   checkProcess: Ejecuta el procedimiento para el recalculo de puntos por envase
  //*
  checkProcess: async function() {

    //DEBUG
    console.log("**checkProcess**");

    const { nextProcess } = this.meta.methods;

    await nextProcess().send({
            from: this.account
        }, function(error, transactionHash){
            if (error) {
                console.error("Error nextProcess: ", error);
                showMessage("Error. Transacción no completada");
                alert("Error. Transacción no completada.");
            } else {
                console.info("Transaction hash: ", transactionHash);
                showMessage("Petición de actualización enviada.");
            }
        }
    );

    //DEBUG
    console.log("**checkProcess getStatusValues**");

    this.getStatusValues();

  },

  //*
  //* updatePointValues: Actualiza los valores utilizados para el recalculo de puntos 
  //* por envase
  //*
  updatePointValues: async function() {

    //DEBUG
    console.log("**updatePointValues**");

    const PACK1 = 0;
    const PACK2 = 1;
    const PACK3 = 2;

    const pointsMin1 = document.getElementById("points-min1");      
    const pointsMax1 = document.getElementById("points-max1");
    const priceMin1 = document.getElementById("price-min1");
    const priceMax1 = document.getElementById("price-max1");

    const pointsMin2 = document.getElementById("points-min2");      
    const pointsMax2 = document.getElementById("points-max2");
    const priceMin2 = document.getElementById("price-min2");
    const priceMax2 = document.getElementById("price-max2");

    const pointsMin3 = document.getElementById("points-min3");      
    const pointsMax3 = document.getElementById("points-max3");
    const priceMin3 = document.getElementById("price-min3");
    const priceMax3 = document.getElementById("price-max3");

    priceMin2.value = priceMin1.value;
    priceMax2.value = priceMax1.value;

    //DEBUG
    console.log("**updatePointValues step 1**");

    // Se verifica que los valores de los campos de input son válidos 
    if (pointsMin1.checkValidity() && pointsMax1.checkValidity() && 
        priceMin1.checkValidity() && priceMax1.checkValidity() &&
        pointsMin2.checkValidity() && pointsMax2.checkValidity() && 
        pointsMin3.checkValidity() && pointsMax3.checkValidity() && 
        priceMin3.checkValidity() && priceMax3.checkValidity()) {

        //DEBUG
        console.log("**updatePointValues step 2**");

        if (pointsMin1.value != this.valuesPerPack[PACK1][1] || pointsMax1.value != this.valuesPerPack[PACK1][2] ||
            priceMin1.value != this.valuesPerPack[PACK1][3] || priceMax1.value != this.valuesPerPack[PACK1][4] ||
            pointsMin2.value != this.valuesPerPack[PACK2][1] || pointsMax2.value != this.valuesPerPack[PACK2][2] ||
            pointsMin3.value != this.valuesPerPack[PACK3][1] || pointsMax3.value != this.valuesPerPack[PACK3][2] ||
            priceMin3.value != this.valuesPerPack[PACK3][3] || priceMax3.value != this.valuesPerPack[PACK3][4]) {

            //DEBUG
            console.log("**updatePointValues step 3**");

            let min1 = priceMin1.value * this.DEC_POS_DIV;
            let max1 = priceMax1.value * this.DEC_POS_DIV;
            let min3 = priceMin3.value * this.DEC_POS_DIV;
            let max3 = priceMax3.value * this.DEC_POS_DIV;

            //DEBUG
            console.log("Price Min1: ", min1);
            console.log("Price Max1: ", max1);

            const { setPointsPackaging } = this.meta.methods;

            await setPointsPackaging(pointsMin1.value, pointsMax1.value, pointsMin2.value, 
                pointsMax2.value, pointsMin3.value, pointsMax3.value, min1, max1,
                min3, max3).send({
                from: this.account
            }, function(error, transactionHash){
                if (error) {
                    console.error("Error setPointsPackaging: ", error);
                    showMessage("Error. Transacción no completada");
                    alert("Error. Transacción no completada.");
                } else {

                    document.getElementById("points1").value = pointsMin1.value;
                    document.getElementById("points2").value = pointsMin2.value;
                    document.getElementById("points3").value = pointsMin3.value;
        
                    console.info("Transaction hash: ", transactionHash);
                    showMessage("Actualización realizada. Espere confirmación.");
                }
            });

        }

    } else {
        this.setStatus("ERROR. Datos de entrada no válidos.");
        alert("ERROR. Datos de entrada no válidos.");
    }

  },

  //*
  //* updateEthPrices: Actualiza rango de precio de referencia del Ether
  //*
  updateEthPrices: async function() {

    //DEBUG
    console.log("**updateEthPrices**");

    const _priceEthMin = document.getElementById("priceethmin");      
    const _priceEthMax = document.getElementById("priceethmax");

    // Se verifica que los valores de los campos de input son válidos 
    if (_priceEthMin.checkValidity() && _priceEthMax.checkValidity()) {

        if (_priceEthMin.value != this.priceEthMin || _priceEthMax.value != this.priceEthMax) {

            let ethMin = _priceEthMin.value * this.DEC_POS_DIV;
            let ethMax = _priceEthMax.value * this.DEC_POS_DIV;

            //DEBUG
            console.log("Price Eth Min: ", ethMin);
            console.log("Price Eth Max: ", ethMax);

            const { setRangeEthPrice } = this.meta.methods;

            await setRangeEthPrice(ethMin, ethMax).send({
                from: this.account
            }, function(error, transactionHash){
                if (error) {
                    console.error("Error setPointsPackaging: ", error);
                    showMessage("Error. Transacción no completada");
                    alert("Error. Transacción no completada.");
                } else {
                    console.info("Transaction hash: ", transactionHash);
                    showMessage("Actualización realizada. Espere confirmación.");
                }
            });

        }

    } else {
        this.setStatus("ERROR. Datos de entrada no válidos.");
        alert("ERROR. Datos de entrada no válidos.");
    }

  },

  //*
  //* updateOtherValues: Valida y actualiza los valores de los otros parámetros utilizados
  //*                    en el oráculo.
  //*
  updateOtherValues: async function() {

    //DEBUG
    console.log("**updateOtherValues**");    

    const blocksPeriod = document.getElementById("blocks-period");      
    const blocksRequest = document.getElementById("blocks-request");
    const limitGasLow = document.getElementById("limit-gas-low");
    const limitGasMed = document.getElementById("limit-gas-med");
    const limitGasHigh = document.getElementById("limit-gas-high");      

    // Se verifica que los valores de los campos de input son válidos 
    if (blocksPeriod.checkValidity() && blocksRequest.checkValidity() && 
        limitGasLow.checkValidity() && limitGasMed.checkValidity() &&
        limitGasHigh.checkValidity()) {

        //DEBUG
        console.log("**updateOtherValues step 1**");                

        if (blocksPeriod.value != this.otherValues[0] || blocksRequest.value != this.otherValues[1] ||
            limitGasLow.value != this.otherValues[2] || limitGasMed.value != this.otherValues[3] ||
            limitGasHigh.value != this.otherValues[4]) {

        //DEBUG
        console.log("**updateOtherValues step 2**");                                

            const { setOtherValues } = this.meta.methods;

            await setOtherValues(blocksPeriod.value, blocksRequest.value, limitGasLow.value, 
                limitGasMed.value, limitGasHigh.value).send({
                from: this.account
            }, function(error, transactionHash){
                if (error) {
                    console.error("Error setOtherValues: ", error);
                    showMessage("Error. Transacción no completada");
                    alert("Error. Transacción no completada.");
                } else {
                    console.info("Transaction hash: ", transactionHash);
                    showMessage("Actualización realizada. Espere confirmación.");
                }
            });

            this.getStatusValues();

        }

    } else {
        this.setStatus("ERROR. Datos de entrada no válidos.");
        alert("ERROR. Datos de entrada no válidos.");
    }

  },

  //*
  //* getValuesPerPack: Obtiene los valores de los parámetros para la asignación de puntos
  //*
  getValuesPerPack: async function() {

    //DEBUG 
    console.log("**getValuesPerPack**");

    const { getValuesPerPack } = this.meta.methods;

    let _values = await getValuesPerPack(0).call();

    //DEBUG
    console.log("ValuesPerPack 0:", _values);

    _values[3] = Math.trunc(_values[3]/this.DEC_POS_DIV);
    _values[4] = Math.trunc(_values[4]/this.DEC_POS_DIV);

    this.valuesPerPack[0] = _values;

    document.getElementById("points1").focus();
    document.getElementById("points1").value = _values[0];
    document.getElementById("points-min1").value = _values[1];
    document.getElementById("points-max1").value = _values[2];
    document.getElementById("price-min1").value = _values[3];
    document.getElementById("price-max1").value = _values[4];

    _values = await getValuesPerPack(1).call();

    //DEBUG
    console.log("ValuesPerPack 1:", _values);

    _values[3] = Math.trunc(_values[3]/this.DEC_POS_DIV);
    _values[4] = Math.trunc(_values[4]/this.DEC_POS_DIV);

    this.valuesPerPack[1] = _values;

    document.getElementById("points2").value = _values[0];
    document.getElementById("points-min2").value = _values[1];
    document.getElementById("points-max2").value = _values[2];
    document.getElementById("price-min2").value = _values[3];
    document.getElementById("price-max2").value = _values[4];

    _values = await getValuesPerPack(2).call();

    //DEBUG
    console.log("ValuesPerPack 2:", _values);

    _values[3] = Math.trunc(_values[3]/this.DEC_POS_DIV);
    _values[4] = Math.trunc(_values[4]/this.DEC_POS_DIV);

    this.valuesPerPack[2] = _values;

    document.getElementById("points3").value = _values[0];
    document.getElementById("points-min3").value = _values[1];
    document.getElementById("points-max3").value = _values[2];
    document.getElementById("price-min3").value = _values[3];
    document.getElementById("price-max3").value = _values[4];

  },

  //*
  //* getEthValues: Obtiene los valores de los parámetros para el precio del Ether
  //*
  getEthValues: async function() {

    //DEBUG 
    console.log("**getEthValues**");

    const { getEthValues } = this.meta.methods;

    let _values = await getEthValues().call();   

    //DEBUG
    console.log("Eth Values: ", _values);

    _values[0] = Math.trunc(_values[0]/this.DEC_POS_DIV);
    _values[1] = Math.trunc(_values[1]/this.DEC_POS_DIV);
    
    document.getElementById("priceethmin").value = _values[0];
    document.getElementById("priceethmax").value = _values[1];    

    this.priceEthMin = _values[0];
    this.priceEthMax = _values[1];

  },

  //*
  //* getStatusValues:
  //*
  getStatusValues: async function() {

    //DEBUG 
    console.log("**getStatusValues**");

    // Recupera contador queries pendientes de respuesta
    const { countQueryInProgress } = this.meta.methods;

    let _value = await countQueryInProgress().call();

    document.getElementById("pending-queries").innerHTML = _value;

    //DEBUG
    console.log("Queries pendientes: ", _value);    

    // Recupera saldo
    const { getContractBalance } = this.meta.methods;

    _value = await getContractBalance().call();

    let balance = (parseInt(_value)/1000000000000000000).toFixed(4);

    //DEBUG
    console.log("Saldo contrato: ", balance);

    document.getElementById("balance").innerHTML = balance.toString() + " ETH";

    // Recupera último bloque en que se recalcularon los puntos
    const { prevBlock } = this.meta.methods;

    _value = await prevBlock().call();

    let block = parseInt(_value);
    document.getElementById("prev-block").innerHTML = block;

    //DEBUG
    console.log("Bloque anterior: ", _value);

    // Se recupera el período de revisión
    const { blocksPeriod } = this.meta.methods;

    _value = await blocksPeriod().call();

    console.log("Block period: ", parseInt(_value));

    block += parseInt(_value);

    document.getElementById("next-block").innerHTML = block;

    //DEBUG
    console.log("Next bloque: ", block);
  },

  //*
  //* getOtherValues: 
  //*
  getOtherValues: async function() {

    //DEBUG 
    console.log("**getOtherValues**");

    // Se recuperan restos de valores
    const { getOtherValues } = this.meta.methods;

    let _values = await getOtherValues().call();

    document.getElementById("blocks-period").value = _values[0];
    document.getElementById("blocks-request").value = _values[1];
    document.getElementById("limit-gas-low").value = _values[2];
    document.getElementById("limit-gas-med").value = _values[3];
    document.getElementById("limit-gas-high").value = _values[4];

    this.otherValues = _values;

    //DEBUG
    console.log("Other values: ", _values);
  },

  //*
  //*   getIsAdmin: Determinar si la dirección es Admin
  //*
  getIsAdmin: async function() {

    this.setStatus("Valida si la dirección es Admin");

    const { isAdmin } = this.meta.methods;

    await isAdmin(this.account).call(function(error, response){

        if (error) {
            showMessage(error);
            console.error(error);
        } else {
            //Debug
            console.log("Response isAdmin: ", response);
            this.isAdmin = response;            
        }
    }.bind(this));
  },


  //*
  //*   getOwner: Recupera la dirección del owner
  //*
  getOwner: async function() {

    this.setStatus("Se recupera owner del contrato");

    const { owner } = this.meta.methods;
    await owner().call(function(error, response){

        if (error) {
            showMessage(error);
            console.error(error);
        } else {
            const _owner = response;

            document.getElementById("owner").innerHTML = _owner;
            this.owner = _owner;
        }
               
    }.bind(this));
  },

  //*
  //*   getIsPaused: Verifica si se ha detenido el contrato (paused - circuit break)
  //*
  getIsPaused: async function() {

    //DEBUG 
    console.log("**getIsPaused**");

    this.setStatus("Se recupera estado (paused) del contrato");    

    const { paused } = this.meta.methods;
    await paused().call(function(error, response) {

        if (error) {
            showMessage(error);
            console.error(error);
        } else {
            const pauseButton = document.getElementById("pauseButton");
            pauseButton.innerHTML = (response) ? "Unpause":"Pause";
            this.paused = response;
        }
    }.bind(this));
  },  

  //*
  //*   pause: Verifica el estado del contrato (paused/unpaused) para cambiar al estado contrario
  //*
  pause: async function() {

    await this.getIsPaused();

    if (this.paused) {

        const { unpause } = this.meta.methods;
        await unpause().send({
            from: this.account
        }, function(error, transactionHash){
            if (error) {
                console.error("Error unpause: ", error);
                showMessage("Error. Transacción no completada");
                alert("Error. Transacción no completada: " + error);
            } else {
                console.info("Transaction hash: ", transactionHash);
                showMessage("Transacción completada. Espere confirmación.");
            }
        });

    } else {

        const { pause } = this.meta.methods;
        await pause().send({
            from: this.account
        }, function(error, transactionHash){
            if (error) {
                console.error("Error pause: ", error);
                showMessage("Error. Transacción no completada");
                alert("Error. Transacción no completada: " + error);
            } else {
                console.info("Transaction hash: ", transactionHash);
                showMessage("Transacción completada. Espere confirmación.");
            }
        });
    }
  },

  //*
  //* Función para mostrar mensaje de estado
  //*
  setStatus: function(message) {
      document.getElementById("status").innerHTML = message;
  },

};

//*
//* Función para verificar si una variable no tiene valor
//*
function isEmpty(valor) {

  if (valor == null || valor.length == 0 || /^\s+$/.test(valor)) {
      return true;
  } else {
      return false;
  }
};

//*
//* Función para mostrar mensaje de estado (similar a setStatus)
//*
function showMessage(_message) {

    document.getElementById("status").innerHTML = _message;
};

let indAlert = 0;

window.App = App;

window.addEventListener("load", function() {

  if (window.ethereum) {
      // use MetaMask's provider
      App.web3 = new Web3(window.ethereum);
      window.ethereum.enable(); // get permission to access accounts
      showMessage("Web3 detected");

      // Escuchamos los cambios en Metamask para poder detectar un cambio de cuenta
      App.web3.currentProvider.publicConfigStore.on("update", async function(event){
            
        if (typeof event.selectedAddress === "undefined") {

            if (indAlert == 0) {
                alert("Es necesario tener Metamask conectado");
            }
            indAlert = (indAlert + 1) % 5;

        } else {

            console.info("Metamask new address: ", event.selectedAddress);
            console.info("Current address: ", App.account);

            //Debug
            //console.log("TypeOf App.account: ", typeof App.account);

            // Se valida si la cuenta seleccionada en Metamask ha cambiado
            if (event.selectedAddress.toLowerCase() != App.account.toLowerCase()) {

                //Debug
                console.log("Detectada nueva cuenta. Se actualizan los datos.");

                showMessage("Detectada nueva cuenta. Se actualizan los datos.");
                App.start();
            }
        }

      })

  } else {
      console.warn(
          "No web3 detected. Falling back to http://127.0.0.1:9545. You should remove this fallback when you deploy live",
      );
      showMessage("No web3 detected. Falling back to http://127.0.0.1:9545");
      // fallback - use your fallback strategy (local node / hosted node + in-dapp id mgmt / fail)
      App.web3 = new Web3(
          new Web3.providers.HttpProvider("http://127.0.0.1:9545"),
      );
      alert("Es necesario tener instalado Metamask\n para poder utilizar esta Dapp");
  }

  App.start();
});