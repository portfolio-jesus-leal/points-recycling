pragma solidity >= 0.5.0 < 0.6.0;

import "./lib/provableAPI_0.5.sol";
import "./lib/SafeMath.sol";
import "./lib/Pausable.sol";

/**
 * 	@dev CustomOracle: Implementa toda la lógica relacionada con el cálculo de puntos entregados
 *  a cambio de envases y de actualizar periódicamente los puntos por unidad, basado en ciertos
 *  parametros del contrato y en una serie de variables off-chain.
 **/
contract CustomOracle is usingProvable, Pausable {

    using SafeMath for uint;

	/**
     *  Constantes inicialización
     **/
	uint constant private BLOCKS_PERIOD = 40000;
	uint constant private BLOCKS_REQUEST_ALLOW = 6000;
	uint constant private GAS_LIMIT_LOW = 150000;
	uint constant private GAS_LIMIT_MED = 200000;
	uint constant private GAS_LIMIT_HIGH = 380000;

	/**
	 *  Constantes
     **/
	uint constant private MAX_VALUE_LIMIT = 1000;
	uint constant private DEC_POS_DIV = 10000;
	uint constant private DECIMAL_POS = 4;
	uint constant private ONE_CENT = 100;
	uint constant private PACKAGING_ITEMS = 3;
	uint constant private PACK1 = 0;
	uint constant private PACK2 = 1;
	uint constant private PACK3 = 2;

	/**
     *  Variables control de frecuencia
     **/
    uint private lastReqRANDOM;
    uint private lastReqOIL;
    uint private lastReqPET;
    uint private lastReqALUMINUM;
    uint private lastReqETHEUR;
    uint private lastReqUSDEUR;
    uint private lastReqDATE;
    uint private aluminumPrice;
    uint private petPrice;

	/**
	 *  Variables públicas
     **/
    uint public priceEthMin;
    uint public priceEthMax;
    uint public rangeEthPrice;
    uint public prevBlock;

    uint public gasLimitLow;
    uint public gasLimitMed;
    uint public gasLimitHigh;
    uint public blocksPeriod;
    uint public blocksRequest;

    uint public randomNumber;
    uint public rateETHEUR;
    string public dateTime;

    address payable public owner;

	/**
     *  Tipos posibles de queries enviadas por el oráculo
     **/
    enum QueryType{
        RANDOM,         // Número aleatorio
        PET,            // Precio plástico PET
        ALUMINUM,       // Precio aluminio
        ETHEUR,         // Tipo de cambio Ether - Euro
        DATE            // Fecha y hora actual
    }

	/**
     *  Struct con campos asociados a los puntos dados por envase
     **/
    struct PointsPerPackaging {
        uint pointsPerPack;
        uint pointsMin;
        uint pointsMax;
        uint priceMin;
        uint priceMax;
    }

	/**
     *  Datos queries en progreso
    **/
    struct queryData {
        bool inProgress;
        QueryType qType;
    }

	/**
     *  Mapping para el control de queries en progreso
     **/
    mapping (bytes32 => queryData) private queryInProgress;

	/**
     *  Contador de queries en progreso (enviadas al oráculo y pendiente de recibir respuesta)
     *  Sirve para controlar si hay queries que se estén quedando sin respuesta
     **/
    uint public countQueryInProgress;    

    /**
     * Array con información campos asociados a los puntos dados por envase
     **/
    PointsPerPackaging[PACKAGING_ITEMS] public packaging;

    /**
     *    Eventos
     **/
    event LogNewProvableQuery(address indexed myAddress, string description);
    event generateNewValue(address indexed myAddress, string description, string value);
    event generatedRandomNumber(address indexed myAddress, uint256 randomNumber);
    event currentDateTime(address indexed myAddress, string currentDateTime);
    event newPointsReward(address indexed myAddress, string packaging, uint points);
    event packagingUpdate(address indexed myAddress, uint ind, uint points, uint pointsMin, uint pointsMax, uint priceMin, uint priceMax);
    event packagingFullUpdate(address indexed myAddress);
    event ethPriceUpdate(address indexed myAddress, uint priceEthMin, uint priceEthMax);
    event limitGasUpdate(address indexed myAddress, uint gasLimitLow, uint gasLimitMed, uint gasLimitHigh);
    event blockPeriodUpdate(address indexed myAddress, uint blocksPeriod);
    event blockRequestUpdate(address indexed myAddress, uint blocksRequest);
    event otherValuesFullUpdate(address indexed myAddress);

    /**
     * @dev Valida la frecuencia de una petición al oráculo
     *
     * @param _lastRequest Número de bloques en la última petición
     **/
    modifier checkLastRequest(uint _lastRequest) {
        require(_lastRequest + blocksRequest < block.number, "Request not allowed. Too frequent");
        _;
    }

    /**
     * @dev Constructor
     *      Iniciailiza los parámetros con los valores por defecto
     **/
    constructor()
        payable
        public
    {
        blocksPeriod = BLOCKS_PERIOD;
        blocksRequest = BLOCKS_REQUEST_ALLOW;
        gasLimitLow = GAS_LIMIT_LOW;
        gasLimitMed = GAS_LIMIT_MED;
        gasLimitHigh = GAS_LIMIT_HIGH;
        owner = msg.sender;

        initializePointsArray();
    }

    /**
     * @dev Calcula el total de puntos que corresponden según la cantidad de envases entregados
     *
     * @param _pack1Qty     Cantidad envases pack1
     * @param _pack2Qty     Cantidad envases pack2
     * @param _pack3Qty     Cantidad envases pack3
     * @return _totalPoints Total de puntos
     **/
    function calculatePoints(uint _pack1Qty, uint _pack2Qty, uint _pack3Qty)
        public
        view
        returns(uint _totalPoints)
    {
        if (_pack1Qty.add(_pack2Qty).add(_pack3Qty) > 0) {
            _totalPoints = _pack1Qty.mul(packaging[PACK1].pointsPerPack).add(
                           _pack2Qty.mul(packaging[PACK2].pointsPerPack).add(
                           _pack3Qty.mul(packaging[PACK3].pointsPerPack)));
        } else {
            _totalPoints = 0;
        }
    }

    /**
     * @dev Devuelve el número de puntos que corresponde a cada uno de los envases
     *
     * @return _pointsPack1 Puntos por pack1
     * @return _pointsPack2 Puntos por pack2
     * @return _pointsPack3 Puntos por pack3
     **/
    function getPointsPerPack()
        public
        view
        returns(uint _pointsPack1, uint _pointsPack2, uint _pointsPack3)
    {
        _pointsPack1 = packaging[PACK1].pointsPerPack;
        _pointsPack2 = packaging[PACK2].pointsPerPack;
        _pointsPack3 = packaging[PACK3].pointsPerPack;
    }

    /**
     * @dev Devuelve los valores utilizados en el cálculo de puntos para un tipo de envase
     *
     * @param _ind Indice array de datos
     *
     * @return _pointsPerPack Puntos por envase
     * @return _pointsMin Puntos mínimos permitidos
     * @return _pointsMax Puntos máximo permitidos
     * @return _priceMin Precio mínimo de referencia
     * @return _priceMax Precio máximo de referencia
     **/
    function getValuesPerPack(uint _ind)
        public
        view
        returns(uint _pointsPerPack, uint _pointsMin, uint _pointsMax, uint _priceMin, uint _priceMax)
    {
        require(_ind < PACKAGING_ITEMS, "Index value is not valid");
        
        _pointsPerPack = packaging[_ind].pointsPerPack;
        _pointsMin = packaging[_ind].pointsMin;
        _pointsMax = packaging[_ind].pointsMax;
        _priceMin = packaging[_ind].priceMin;
        _priceMax = packaging[_ind].priceMax;
    }

    /**
     * @dev Devuelve los precios de referencia del Ether
     *
     * @return _priceMin Precio mínimo de referencia para el Ether
     * @return _priceMax Precio máximo de referencia para el Ether
     **/
    function getEthValues()
        public
        view
        returns(uint _priceMin, uint _priceMax)
    {
        _priceMin = priceEthMin;
        _priceMax = priceEthMax;
    }

    /**
     * @dev Devuelve otros valores utilizados en la gestión del oráculo
     *
     * @return _blocksPeriod Frecuencia (en bloques) con que se revisarán los puntos a asignar por envase
     * @return _blocksRequest Frecuencia mínima (en bloques) con la que se puede ejecutar una petición del oráculo
     * @return _gasLimitLow Límite de gas para peticiones con bajo consumo de gas
     * @return _gasLimitMed Límite de gas para peticiones con consumo medio de gas
     * @return _gasLimitHigh Límite de gas para peticiones con alto consumo de gas
     **/
    function getOtherValues()
        public
        view
        returns(uint _blocksPeriod, uint _blocksRequest, uint _gasLimitLow, uint _gasLimitMed, uint _gasLimitHigh)
    {
        _blocksPeriod = blocksPeriod;
        _blocksRequest = blocksRequest;
        _gasLimitLow = gasLimitLow;
        _gasLimitMed = gasLimitMed;
        _gasLimitHigh = gasLimitHigh;
    }

    /**
     * @dev Actualiza otros valores utilizados en la gestión del oráculo
     *
     * @param _blocksPeriod Frecuencia (en bloques) con que se revisarán los puntos a asignar por envase
     * @param _blocksRequest Frecuencia mínima (en bloques) con la que se puede ejecutar una petición del oráculo
     * @param _gasLimitLow Límite de gas para peticiones con bajo consumo de gas
     * @param _gasLimitMed Límite de gas para peticiones con consumo medio de gas
     * @param _gasLimitHigh Límite de gas para peticiones con alto consumo de gas
     **/
    function setOtherValues(uint _blocksPeriod, uint _blocksRequest, uint _gasLimitLow, uint _gasLimitMed, uint _gasLimitHigh)
        public
        onlyAdmin
        whenNotPaused
    {
        setGasLimit(_gasLimitLow, _gasLimitMed, _gasLimitHigh);
        setBlocksPeriod(_blocksPeriod);
        setBlocksRequest(_blocksRequest);

        emit otherValuesFullUpdate(address(this));
    }

    /**
     * @dev Permite especificar el número de bloques que deberán confirmarse antes de volver a actualizar la información de puntos.
     *
     * @param _blocksPeriod Número de bloques (Si _blocksPeriod = 0, se tomar el valor por defecto)
     **/
    function setBlocksPeriod(uint _blocksPeriod)
        internal
    {
        if (_blocksPeriod == 0) {
            blocksPeriod = BLOCKS_PERIOD;
        } else {
            blocksPeriod = _blocksPeriod;
        }
        emit blockPeriodUpdate(address(this), blocksPeriod);
    }

    /**
     * @dev Permite especificar el número de bloques que deberán confirmarse antes de volver a actualizar la información de puntos.
     *
     * @param _blocksRequest Número de bloques (Si _blocksPeriod = 0, se tomar el valor por defecto)
     **/
    function setBlocksRequest(uint _blocksRequest)
        internal
    {
        if (_blocksRequest == 0) {
            blocksRequest = BLOCKS_REQUEST_ALLOW;
        } else {
            blocksRequest = _blocksRequest;
        }
        emit blockRequestUpdate(address(this), blocksRequest);
    }

    /**
     * @dev Actualiza las variables para el limite de gas utilizadas en el envío de queries al oráculo
     *
     * Se establecen tres posibles niveles:
     * @param _lowLimit Límite bajo (Utilizado en DATE)
     * @param _medLimit Límite medio (Utilizado en RANDOM, USDEUR, OIL)
     * @param _highLimit Límite alto (Utilizado en ALUMINUM, ETHEUR, PET)
     **/
    function setGasLimit(uint _lowLimit, uint _medLimit, uint _highLimit)
        internal
    {
        require(_lowLimit >= GAS_LIMIT_LOW, "Gas limit (low) is too low");
        require(_lowLimit < _medLimit, "Low limit must be lower than medium limit");
        require(_medLimit >= GAS_LIMIT_MED, "Gas limit (med) is too low");
        require(_medLimit < _highLimit, "Medium limit must be lower than high limit");
        require(_highLimit >= GAS_LIMIT_HIGH, "Gas limit (high) is too low");

        gasLimitLow = _lowLimit;
        gasLimitMed = _medLimit;
        gasLimitHigh = _highLimit;

        emit limitGasUpdate(address(this), gasLimitLow, gasLimitMed, gasLimitHigh);
    }

    /**
     *
     * @dev El cálculo de los puntos se hace asumiendo 4 posiciones decimales para todos los campos con precios
     *      Por tanto, para que un campo tenga el valor 1, se deberá enviar 10000.
     *
     * @param _ind Indice del elemento dentro de packaging que se quiere modificar
     * @param _pointsMin Número mínimo de puntos a entregar por cada envase
     * @param _pointsMax Número máximo de puntos a entregar por cada envase
     * @param _priceMin Valor mínimo del precio utilizado como referencia para el cálculo de puntos
     * @param _priceMax Valor máximo del precio utilizado como referencia para el cálculo de puntos
     **/
    function setPointsPerPackaging(uint _ind, uint _pointsMin, uint _pointsMax, uint _priceMin, uint _priceMax)
        public
        onlyAdmin
        whenNotPaused
    {
		require(_ind < PACKAGING_ITEMS, "Index value is not valid");
		require(_pointsMin > 0, "Minimun points value is not greater than zero");
		require(_pointsMax < MAX_VALUE_LIMIT, "Maximun points value is not valid");
		require(_pointsMin <= _pointsMax, "Values for points are not valid");
		require(_priceMin <= _priceMax, "Value for prices are not valid");

        packaging[_ind].pointsPerPack = _pointsMin;
        packaging[_ind].pointsMin = _pointsMin;
        packaging[_ind].pointsMax = _pointsMax;

        if (_priceMin > 0) { packaging[_ind].priceMin = _priceMin; }
        if (_priceMax > 0) { packaging[_ind].priceMax = _priceMax; }

        emit packagingUpdate(address(this), _ind, _pointsMin, _pointsMin, _pointsMax, _priceMin, _priceMax);
    }

    /**
     *
     * @dev Unifica la actualización de los parámetros utilizados en el cálculo automático
     *      de puntos por envase
     *
     * @param _pointsMin1 Número mínimo de puntos a entregar por cada envase
     * @param _pointsMax1 Número máximo de puntos a entregar por cada envase
     * @param _pointsMin2 Número mínimo de puntos a entregar por cada envase
     * @param _pointsMax2 Número máximo de puntos a entregar por cada envase
     * @param _pointsMin3 Número mínimo de puntos a entregar por cada envase
     * @param _pointsMax3 Número máximo de puntos a entregar por cada envase
     * @param _priceMinPet Valor mínimo del precio utilizado como referencia para el cálculo de puntos
     * @param _priceMaxPet Valor máximo del precio utilizado como referencia para el cálculo de puntos
     * @param _priceMinAlu Valor mínimo del precio utilizado como referencia para el cálculo de puntos
     * @param _priceMaxAlu Valor máximo del precio utilizado como referencia para el cálculo de puntos
     **/
    function setPointsPackaging(
        uint _pointsMin1, uint _pointsMax1,
        uint _pointsMin2, uint _pointsMax2,
        uint _pointsMin3, uint _pointsMax3,
        uint _priceMinPet, uint _priceMaxPet,
        uint _priceMinAlu, uint _priceMaxAlu
    )
        public
        onlyAdmin
        whenNotPaused
    {
        setPointsPerPackaging(PACK1, _pointsMin1, _pointsMax1, _priceMinPet, _priceMaxPet);
        setPointsPerPackaging(PACK2, _pointsMin2, _pointsMax2, _priceMinPet, _priceMaxPet);
        setPointsPerPackaging(PACK3, _pointsMin3, _pointsMax3, _priceMinAlu, _priceMaxAlu);

        emit packagingFullUpdate(address(this));
    }

    /**
     * @dev Actualiza los valores para el rango de precios del Ether utilizado como referencia para el cálculo de puntos
     *
     * @param _priceEthMin Valor mínimo del precio del Ether utilizado como referencia para el cálculo de puntos
     * @param _priceEthMax Valor máximo del precio del Ether utilizado como referencia para el cálculo de puntos
     **/
    function setRangeEthPrice(uint _priceEthMin, uint _priceEthMax)
        public
        onlyAdmin
        whenNotPaused
    {
		require(_priceEthMin > ONE_CENT, "Minimun Ether price must be at least 1 cent");
		require(_priceEthMin <= _priceEthMax, "Value for prices are not valid");

        priceEthMin = _priceEthMin;
        priceEthMax = _priceEthMax;

        // Calcula el rango entre precio mínimo y precio máximo del Ether
        rangeEthPrice = priceEthMax.sub(priceEthMin);

        emit ethPriceUpdate(address(this), priceEthMin, priceEthMax);
    }

    /**
     * @dev Comprueba mediante el número del bloque si se deben actualizar los precios
     *      utilizados como referencia para el cálculo de puntos entregados por envase
     *
     * @return indicador de actualización
     **/
	function checkNextProcess()
        public
        view
        returns(bool)
    {
        if (block.number > prevBlock + blocksPeriod && !paused()) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Recupera los valores necesarios para actualizar los puntos entregados por envase
     **/
	function nextProcess()
	    public
	    whenNotPaused
	{
		if (checkNextProcess()) {

			prevBlock = block.number;

			newEthEurRateRequest(1);
			newPetPriceRequest();
			newAluminumPriceRequest();
		}
	}

    /**
     * @dev Trata la respuesta a la query enviada al oráculo
     **/
    function __callback(
        bytes32 _queryId,
        string memory _result
    )
        public
    {
        require(msg.sender == provable_cbAddress(), 'Sender is not valid');
        require(queryInProgress[_queryId].inProgress == true, 'Query not found');

        if (queryInProgress[_queryId].qType == QueryType.RANDOM) {

            randomNumber = parseInt(_result);
            emit generatedRandomNumber(address(this), randomNumber);

        } else if (queryInProgress[_queryId].qType == QueryType.PET) {

            petPrice = parseInt(_result, DECIMAL_POS);
            emit generateNewValue(address(this), "PET", _result);

        } else if (queryInProgress[_queryId].qType == QueryType.ALUMINUM) {

            aluminumPrice = parseInt(_result, DECIMAL_POS);
            emit generateNewValue(address(this), "ALUMINUM", _result);

        } else if (queryInProgress[_queryId].qType == QueryType.ETHEUR) {

            rateETHEUR = parseInt(_result, DECIMAL_POS);
            emit generateNewValue(address(this), "ETHEUR", _result);

        } else if (queryInProgress[_queryId].qType == QueryType.DATE) {

            dateTime = _result;
            emit currentDateTime(address(this), _result);

        }

        delete queryInProgress[_queryId];
        countQueryInProgress = countQueryInProgress.sub(1);

        // Si ya se tiene el precio del plástico PET y del tipo de cambio ETH/EUR se calculan los puntos para los envases PET
        if (petPrice > 0 && rateETHEUR > 0) {

            packaging[PACK1] = calculatePointsReward(petPrice, rateETHEUR, packaging[PACK1]);
            packaging[PACK2] = calculatePointsReward(petPrice, rateETHEUR, packaging[PACK2]);

            emit newPointsReward(address(this), "PACK1", packaging[PACK1].pointsPerPack);
            emit newPointsReward(address(this), "PACK2", packaging[PACK2].pointsPerPack);

            petPrice = 0;
        }

        // Si ya se tiene el precio del aluminio y del tipo de cambio ETH/EUR se calculan los puntos para las latas
        if (aluminumPrice > 0 && rateETHEUR > 0) {

            packaging[PACK3] = calculatePointsReward(aluminumPrice, rateETHEUR, packaging[PACK3]);

            emit newPointsReward(address(this), "PACK3", packaging[PACK3].pointsPerPack);

            aluminumPrice = 0;
        }
    }

    /**
     * @dev Actualiza la cantidad de puntos a entregar por envase según los parámetros de entrada
     *
     * @param _price Precio utilizado como referencia
     * @param _priceEth Precio del Ether
     * @param _ppp Variable struct con los valores asociados a los puntos
     *
     * @return _ppp Devuelve la variable struct actualizada
     **/
    function calculatePointsReward(
        uint _price,
        uint _priceEth,
        PointsPerPackaging memory _ppp
    )
        internal
        returns (PointsPerPackaging memory)
    {
		require(_price > 0, "Price can not be zero");
		require(_priceEth > 0, "Ether price can not be zero");

        uint _rangePoints = 0;
        uint _rangePrice = 0;
        uint _diffPrice = 0;
        uint _diffEthPrice = 0;
        uint _pointsPerPrice = 0;
        uint _pointsPerEth = 0;

        // ** Calcula diferencia entre el precio mínimo y el precio actual de referencia
        if (_ppp.priceMin < _price && _ppp.priceMin != 0) {
            _diffPrice = _price.sub(_ppp.priceMin);
            if (_ppp.priceMax < _price) {
                _ppp.priceMax = _price;
            }
        } else {
            _ppp.priceMin = _price;
        }

        // ** Calcula diferencia entre el precio mínimo y el precio actual del Ether
        if (priceEthMin < _priceEth && priceEthMin != 0) {
            _diffEthPrice = _priceEth.sub(priceEthMin);
         } else {
            priceEthMin = _priceEth;
        }

        if (priceEthMax < _priceEth) {
            priceEthMax = _priceEth;
        }
        rangeEthPrice = priceEthMax.sub(priceEthMin);

        // ** Calcula rango entre precio mínimo y precio máximo
        if (_ppp.priceMin < _ppp.priceMax) {
            _rangePrice = _ppp.priceMax.sub(_ppp.priceMin);
        } else {
            _ppp.priceMax = _ppp.priceMin;
        }

        // ** Calcula el rango entre el mínimo y máximo de puntos que se pueden asignar
        if (_ppp.pointsMin < _ppp.pointsMax) {

            _rangePoints = _ppp.pointsMax.sub(_ppp.pointsMin);

			// ** Calcula el reparto del rango de precios entre el rango de puntos (tramos) y
			// ** en base a ellos calcula el factor que indica el tramo del precio actual
			// ** Multiplica por DEC_POS_DIV para no perder los decimales
			if (_rangePrice > 0) {
				_pointsPerPrice = _diffPrice.mul(DEC_POS_DIV).div(_rangePrice.div(_rangePoints));
			}

			if (rangeEthPrice > 0){
				_pointsPerEth = _diffEthPrice.mul(DEC_POS_DIV).div(rangeEthPrice.div(_rangePoints));
			}

        } else {
            _ppp.pointsMax = _ppp.pointsMin;
        }

        // ** Puntos = Puntos mínimos + factor - factor Eth
        _ppp.pointsPerPack = _ppp.pointsMin.mul(DEC_POS_DIV).add(_pointsPerPrice).sub(_pointsPerEth).div(DEC_POS_DIV);

        // ** Se valida se mantenga en el rango de puntos establecidos
        if (_ppp.pointsPerPack < _ppp.pointsMin) {
            _ppp.pointsPerPack = _ppp.pointsMin;
        } else if (_ppp.pointsPerPack > _ppp.pointsMax) {
            _ppp.pointsPerPack = _ppp.pointsMax;
        }

        return (_ppp);
    }

    /**
     * @dev Prepara query para solicitar número aleatorio
     *
     * @param _min Valor mínimo del rango
     * @param _max Valor máximo del rango
     */
    function newRandomRequest(uint _min, uint _max)
        public
        payable
        whenNotPaused
        checkLastRequest(lastReqRANDOM)
    {
        require(_max > _min, "Max value is not greater than Min value");

        string memory query = string(abi.encodePacked("https://www.random.org/integers/?num=1&min=", uint2str(_min), "&max=", uint2str(_max), "&col=1&base=10&format=plain&rnd=new"));
        queryURLRequestPayable(query, QueryType.RANDOM, gasLimitMed);
        lastReqRANDOM = block.number;
    }

    /**
     * @dev Prepara query para convertir un importe en Ethers a Euros
     *
     * @param _amount Importe a convertir (1 para obtener tipo de cambio)
     */
    function newEthEurRateRequest(uint _amount)
        internal
        checkLastRequest(lastReqETHEUR)
    {
        require(_amount > 0, "Amount is not greater than zero");

        // ** Se construye la query con el importe (_amount) enviado como parámetro
        // ** La apiKey ha sido cifrada con la clave pública de Provable
        string memory query = string(abi.encodePacked("[URL] ['json(https://pro-api.coinmarketcap.com/v1/tools/price-conversion?amount=", uint2str(_amount),"&symbol=ETH&convert=EUR&CMC_PRO_API_KEY=${[decrypt] BOHAYhxT0NfxZXzIaeKPXxscUr8RIKD/X4XaQaRzTHhQev26txxN7e3sKijA5kEecTRJyH24mVzHBKi5C/DgQeujq8JJ1kZxAgao0wweVQVhltOzlgv6w4FwF5Jxb8agph+BvdHzGpJPPXm9g6QBd1BNvFny}).data.quote.EUR.price']"));

        queryNestedRequest(query, QueryType.ETHEUR, gasLimitHigh);
        lastReqETHEUR = block.number;
    }

    /**
     * @dev Prepara query para obtener el precio del plástico PET
     **/
    function newPetPriceRequest()
        internal
        checkLastRequest(lastReqPET)
    {
        string memory query = string(abi.encodePacked("[URL] ['json(https://my-json-server.typicode.com/${[decrypt] BId5SdP7IJdwRuOSVDMiWAUu+yIgSahwVggfaOxduiOfFeZGcVEb9ITMP0C9MpPm+0lbzzD5KactQjmWSEcq4t3N9nCyqed0MEI0D90KAzLJEiT4M7OOgrfPW2xBPRXEBxoS}).0.price.EUR']"));

        queryNestedRequest(query, QueryType.PET, gasLimitHigh);
        lastReqPET = block.number;
    }

    /**
     * @dev Prepara query para obtener el precio del aluminio
     **/
    function newAluminumPriceRequest()
        internal
        checkLastRequest(lastReqALUMINUM)
    {
        // La apiKey ha sido cifrada con la clave pública de Provable
        string memory query = string(abi.encodePacked("[URL] ['json(https://www.quandl.com/api/v3/datasets/ODA/PALUM_USD?api_key=${[decrypt] BOXY3msLJlb2O00l9QGbgb+mvJ5sCXNN7muPX1hkIm+cp5LdaVCBmejjb0ctJWuABkjwwlRHeQYsbSg3dmzpznbOquGoXFof0XAL3df8QU/oZzKLp+kFOZvNBXqgxMlh4n+wr9Q=}&rows=1).dataset.data.0.1']"));

        queryNestedRequest(query, QueryType.ALUMINUM, gasLimitHigh);
        lastReqALUMINUM = block.number;
    }

    /**
     * @dev Prepara query para obtener la fecha y hora actual
     **/
    function getCurrentDateTime()
        public
        payable
        whenNotPaused
        checkLastRequest(lastReqDATE)
    {
        string memory query = "json(http://worldclockapi.com/api/json/utc/now).currentDateTime";

        queryURLRequestPayable(query, QueryType.DATE, gasLimitLow);
        lastReqDATE = block.number;
    }

    /**
     *
     * @dev Envío de query al oráculo con una URL simple. El sender paga por la ejecución de la query.
     *      Se devuelve al sender el importe no utilizado.
     *
     * @param _query Query a enviar
     * @param _qType Tipo de query que se envía (para control en callback)
     * @param _gasLimit Límite de gas
     */
    function queryURLRequestPayable(string memory _query, QueryType _qType, uint _gasLimit)
        internal
    {
        require(msg.value > 0, "msg.value is zero");
        require(bytes(_query).length > 0, "Query is empty");
        require(_gasLimit > 0, "Gas limit is zero");

        bytes32 _queryId;
        uint _queryPrice;

        _queryPrice = provable_getPrice("URL", _gasLimit);

        // ** Comprobamos si msg.value es suficiente para el pago de la llamada al oráculo
        if (msg.value < _queryPrice) {

            emit LogNewProvableQuery(address(this), "Provable query was NOT sent, please add some ETH to cover for the query fee");
            revert("msg.value is not enough to cover for the query fee");

        } else {

            _queryId = provable_query("URL", _query, _gasLimit);
            includeQueryInProgress(_queryId, _qType);
 
            msg.sender.transfer(msg.value - _queryPrice);

            emit LogNewProvableQuery(address(this), "Provable URL query was sent, standing by for the answer...");
        }
    }

    /**
     * @dev Envío de query al oráculo con una URL compuesta (Nested - con parámetros o datos cifrados)
     *
     * @param _query Query a enviar
     * @param _qType Tipo de query que se envía (para control en callback)
     * @param _gasLimit Límite de gas
     */
    function queryNestedRequest(string memory _query, QueryType _qType, uint _gasLimit)
        internal
    {
        require(bytes(_query).length > 0, "Query is empty");
        require(_gasLimit > 0, "Gas limit is zero");

        bytes32 _queryId;

        // ** Comprobamos si el contrato tiene saldo suficiente para el pago de la llamada al oráculo
        if (provable_getPrice("NESTED", _gasLimit) > address(this).balance) {

            emit LogNewProvableQuery(address(this), "Provable query was NOT sent, please add some ETH to cover for the query fee");
            revert("ETH balance is not enough to cover for the query fee");

        } else {

            // Enviamos la query a Provable y guardamos el Id para tratarlo en el callback
            _queryId = provable_query("nested", _query, _gasLimit);
            includeQueryInProgress(_queryId, _qType);

            emit LogNewProvableQuery(address(this), "Provable NESTED query was sent, standing by for the answer...");
        }
    }

    /**
     * @dev Guarda el identificado de una query (petición) enviada al oráculo
     *
     * @param _queryId Identificador
     * @param _qType Tipo de query enviada
     **/
    function includeQueryInProgress(bytes32  _queryId, QueryType _qType)
        internal
    {
        queryInProgress[_queryId].inProgress = true;
        queryInProgress[_queryId].qType = _qType;
        countQueryInProgress = countQueryInProgress.add(1);
    }
    

    /**
     * @dev Inicializa con el valor 1 los puntos que se asignarán por defecto a los distintos tipos de envases
     **/
    function initializePointsArray()
        internal
    {
        for (uint _ind = 0; _ind < PACKAGING_ITEMS; _ind++) {
            packaging[_ind].pointsPerPack = 1;
            packaging[_ind].pointsMin = 1;
            packaging[_ind].pointsMax = 1;
        }
    }

    /**
      * @dev Función utilizada para transferir fondos (Ethers) al contrato
      *
      * @param _message  Mensaje que se desea enviar
      * @return _message Devuelve el mismo mensaje de entrada
      */
    function setFunds(string memory _message)
        public
        payable
        returns(string memory)
    {
        require (msg.value > 0, "value is not greater than zero");

        return _message;
    }

    /**
      * @dev Función para transferir el saldo en Ethers del contrato al owner
      *
      * @param _amount Importe a transferir
      */
    function transfer(uint _amount)
        public
        onlyAdmin
        whenNotPaused
    {
        require (getContractBalance() >= _amount, "not enough balance");

        owner.transfer(_amount);
    }

    /**
      * @dev Función para consultar el saldo en Ethers del contrato (necesario para el pago de gas para el Oráculo)
      *
      * @return Saldo tokens de la cuenta con que se esté trabajando
      */
    function getContractBalance()
        public
        view
        returns(uint)
    {
        return address(this).balance;
    }
    
    /**
      * @dev Fallback function - Called if other functions don't match call or
      * sent ether without data
      * Typically, called when invalid data is sent
      * Added so ether sent to this contract is reverted if the contract fails
      * otherwise, the sender's money is transferred to contract
      */
    function ()
        external
        payable
    {
        revert("Fallback function");
    }
}