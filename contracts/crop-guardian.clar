;; crop-guardian
;; Agricultural Crop Monitoring Smart Contract
;; Monitor crop health through IoT sensors, integrate weather and satellite data,
;; automatically trigger insurance payouts for verified losses, and manage
;; sustainable farming certifications

;; constants
(define-constant contract-owner tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-PAYOUT-ALREADY-MADE (err u105))
(define-constant ERR-INVALID-DATA (err u106))
(define-constant ERR-THRESHOLD-NOT-MET (err u107))

;; Policy status constants
(define-constant STATUS-ACTIVE u0)
(define-constant STATUS-SUSPENDED u1)
(define-constant STATUS-EXPIRED u2)
(define-constant STATUS-CLAIMED u3)

;; Weather event types
(define-constant EVENT-DROUGHT u0)
(define-constant EVENT-FLOOD u1)
(define-constant EVENT-HAIL u2)
(define-constant EVENT-FROST u3)
(define-constant EVENT-WIND u4)

;; Sustainability certification levels
(define-constant CERT-ORGANIC u0)
(define-constant CERT-CARBON-NEUTRAL u1)
(define-constant CERT-WATER-EFFICIENT u2)
(define-constant CERT-BIODIVERSITY u3)

;; Risk thresholds
(define-constant DROUGHT-THRESHOLD u30) ;; days without rain
(define-constant FLOOD-THRESHOLD u100) ;; mm rainfall in 24h
(define-constant TEMP-HIGH-THRESHOLD u40) ;; celsius
(define-constant TEMP-LOW-THRESHOLD u0) ;; celsius for frost
(define-constant WIND-THRESHOLD u80) ;; km/h

;; data vars
(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var total-insurance-pool uint u0)
(define-data-var total-payouts-made uint u0)
(define-data-var sustainability-bonus-rate uint u10) ;; 10% bonus

;; data maps
;; Crop insurance policies
(define-map crop-policies uint {
    farmer: principal,
    field-id: (string-ascii 50),
    crop-type: (string-ascii 30),
    field-size: uint, ;; hectares
    coverage-amount: uint,
    premium-paid: uint,
    policy-start: uint,
    policy-end: uint,
    status: uint,
    sustainability-cert: (list 4 uint),
    payout-made: uint,
    last-monitoring: uint
})

;; IoT sensor data storage
(define-map sensor-data {policy-id: uint, timestamp: uint} {
    soil-moisture: uint, ;; percentage
    soil-ph: uint, ;; x100 (e.g., 650 = pH 6.5)
    soil-temperature: uint, ;; celsius
    air-temperature: uint, ;; celsius
    humidity: uint, ;; percentage
    rainfall: uint, ;; mm in 24h
    wind-speed: uint, ;; km/h
    solar-radiation: uint, ;; MJ/m2/day
    crop-health-index: uint ;; 0-100 scale
})

;; Weather event tracking
(define-map weather-events uint {
    policy-id: uint,
    event-type: uint,
    severity: uint, ;; 1-10 scale
    start-timestamp: uint,
    end-timestamp: uint,
    verified-loss: bool,
    payout-triggered: bool,
    payout-amount: uint,
    data-sources: (list 5 (string-ascii 20)) ;; satellite, sensor, weather station
})

;; Satellite and weather data integration
(define-map external-data {policy-id: uint, data-type: (string-ascii 20), timestamp: uint} {
    vegetation-index: uint, ;; NDVI x100
    precipitation: uint, ;; mm
    temperature-avg: uint, ;; celsius
    cloud-cover: uint, ;; percentage
    drought-index: uint, ;; 0-100
    flood-risk: uint, ;; 0-100
    confidence-level: uint ;; data reliability 0-100
})

;; Sustainable farming certifications
(define-map sustainability-records {farmer: principal, certification-type: uint} {
    certification-level: uint,
    issued-date: uint,
    expiry-date: uint,
    carbon-credits: uint,
    water-savings: uint, ;; liters per hectare
    biodiversity-score: uint, ;; 0-100
    soil-health-improvement: uint, ;; 0-100
    verifier: principal
})

;; Yield tracking and prediction
(define-map yield-data {policy-id: uint, season: uint} {
    predicted-yield: uint, ;; tons per hectare x100
    actual-yield: uint, ;; tons per hectare x100
    quality-grade: uint, ;; 1-10
    harvest-timestamp: uint,
    market-price: uint, ;; per ton
    total-revenue: uint,
    insurance-impact: uint ;; percentage of yield protected
})

;; Claims and payout tracking
(define-map insurance-claims uint {
    policy-id: uint,
    claim-type: uint,
    filed-timestamp: uint,
    loss-percentage: uint,
    claim-amount: uint,
    auto-approved: bool,
    payout-timestamp: uint,
    verification-sources: (list 3 (string-ascii 20)),
    adjuster-notes: (string-ascii 200)
})

;; public functions

;; Register crop insurance policy
(define-public (register-crop-policy
    (field-id (string-ascii 50))
    (crop-type (string-ascii 30))
    (field-size uint)
    (coverage-amount uint)
    (premium-paid uint)
    (policy-duration uint))
    (let (
        (policy-id (var-get next-policy-id))
        (current-time stacks-block-height)
    )
        ;; Validate inputs
        (asserts! (> field-size u0) ERR-INVALID-DATA)
        (asserts! (> coverage-amount u0) ERR-INVALID-DATA)
        (asserts! (> premium-paid u0) ERR-INVALID-DATA)
        
        ;; Create policy
        (map-set crop-policies policy-id {
            farmer: tx-sender,
            field-id: field-id,
            crop-type: crop-type,
            field-size: field-size,
            coverage-amount: coverage-amount,
            premium-paid: premium-paid,
            policy-start: current-time,
            policy-end: (+ current-time policy-duration),
            status: STATUS-ACTIVE,
            sustainability-cert: (list),
            payout-made: u0,
            last-monitoring: current-time
        })
        
        ;; Update insurance pool
        (var-set total-insurance-pool (+ (var-get total-insurance-pool) premium-paid))
        
        ;; Increment policy counter
        (var-set next-policy-id (+ policy-id u1))
        
        (ok policy-id)
    )
)

;; Submit IoT sensor data
(define-public (submit-sensor-data
    (policy-id uint)
    (soil-moisture uint)
    (soil-ph uint)
    (soil-temperature uint)
    (air-temperature uint)
    (humidity uint)
    (rainfall uint)
    (wind-speed uint)
    (solar-radiation uint)
    (crop-health-index uint))
    (let (
        (policy (unwrap! (map-get? crop-policies policy-id) ERR-NOT-FOUND))
        (current-time stacks-block-height)
    )
        ;; Verify farmer or authorized source
        (asserts! (is-eq tx-sender (get farmer policy)) ERR-UNAUTHORIZED)
        
        ;; Check policy is active
        (asserts! (is-eq (get status policy) STATUS-ACTIVE) ERR-INVALID-STATUS)
        
        ;; Store sensor data
        (map-set sensor-data {policy-id: policy-id, timestamp: current-time} {
            soil-moisture: soil-moisture,
            soil-ph: soil-ph,
            soil-temperature: soil-temperature,
            air-temperature: air-temperature,
            humidity: humidity,
            rainfall: rainfall,
            wind-speed: wind-speed,
            solar-radiation: solar-radiation,
            crop-health-index: crop-health-index
        })
        
        ;; Update last monitoring time
        (map-set crop-policies policy-id 
            (merge policy {last-monitoring: current-time})
        )
        
        ;; Check for automatic payout triggers
        (let ((trigger-result (check-payout-triggers policy-id)))
            (ok true)
        )
    )
)

;; Submit external data (satellite, weather stations)
(define-public (submit-external-data
    (policy-id uint)
    (data-type (string-ascii 20))
    (vegetation-index uint)
    (precipitation uint)
    (temperature-avg uint)
    (cloud-cover uint)
    (drought-index uint)
    (flood-risk uint)
    (confidence-level uint))
    (let (
        (policy (unwrap! (map-get? crop-policies policy-id) ERR-NOT-FOUND))
        (current-time stacks-block-height)
    )
        ;; Only owner or authorized oracles can submit
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        
        ;; Store external data
        (map-set external-data {policy-id: policy-id, data-type: data-type, timestamp: current-time} {
            vegetation-index: vegetation-index,
            precipitation: precipitation,
            temperature-avg: temperature-avg,
            cloud-cover: cloud-cover,
            drought-index: drought-index,
            flood-risk: flood-risk,
            confidence-level: confidence-level
        })
        
        (ok true)
    )
)

;; Process automatic payout
(define-public (process-automatic-payout
    (policy-id uint)
    (event-type uint)
    (loss-percentage uint))
    (let (
        (policy (unwrap! (map-get? crop-policies policy-id) ERR-NOT-FOUND))
        (claim-id (var-get next-claim-id))
        (payout-amount (/ (* (get coverage-amount policy) loss-percentage) u100))
    )
        ;; Only owner can process payouts
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        
        ;; Check policy is active and no payout made
        (asserts! (is-eq (get status policy) STATUS-ACTIVE) ERR-INVALID-STATUS)
        (asserts! (is-eq (get payout-made policy) u0) ERR-PAYOUT-ALREADY-MADE)
        
        ;; Validate loss percentage
        (asserts! (and (> loss-percentage u0) (<= loss-percentage u100)) ERR-INVALID-DATA)
        
        ;; Create claim record
        (map-set insurance-claims claim-id {
            policy-id: policy-id,
            claim-type: event-type,
            filed-timestamp: stacks-block-height,
            loss-percentage: loss-percentage,
            claim-amount: payout-amount,
            auto-approved: true,
            payout-timestamp: stacks-block-height,
            verification-sources: (list "iot-sensor" "satellite" "weather-station"),
            adjuster-notes: "Automatic payout triggered by verified data"
        })
        
        ;; Update policy status
        (map-set crop-policies policy-id 
            (merge policy {
                status: STATUS-CLAIMED,
                payout-made: payout-amount
            })
        )
        
        ;; Update counters
        (var-set next-claim-id (+ claim-id u1))
        (var-set total-payouts-made (+ (var-get total-payouts-made) payout-amount))
        
        (ok payout-amount)
    )
)

;; Award sustainability certification
(define-public (award-sustainability-cert
    (farmer principal)
    (cert-type uint)
    (cert-level uint)
    (carbon-credits uint)
    (water-savings uint)
    (biodiversity-score uint)
    (soil-health-improvement uint)
    (validity-period uint))
    (let (
        (current-time stacks-block-height)
    )
        ;; Only owner can award certifications
        (asserts! (is-eq tx-sender contract-owner) ERR-OWNER-ONLY)
        
        ;; Create certification record
        (map-set sustainability-records {farmer: farmer, certification-type: cert-type} {
            certification-level: cert-level,
            issued-date: current-time,
            expiry-date: (+ current-time validity-period),
            carbon-credits: carbon-credits,
            water-savings: water-savings,
            biodiversity-score: biodiversity-score,
            soil-health-improvement: soil-health-improvement,
            verifier: tx-sender
        })
        
        (ok cert-type)
    )
)

;; Record yield data
(define-public (record-yield-data
    (policy-id uint)
    (season uint)
    (actual-yield uint)
    (quality-grade uint)
    (market-price uint))
    (let (
        (policy (unwrap! (map-get? crop-policies policy-id) ERR-NOT-FOUND))
        (field-size (get field-size policy))
        (total-revenue (* actual-yield market-price field-size))
    )
        ;; Only farmer can record yield
        (asserts! (is-eq tx-sender (get farmer policy)) ERR-UNAUTHORIZED)
        
        ;; Store yield data
        (map-set yield-data {policy-id: policy-id, season: season} {
            predicted-yield: u0, ;; To be updated by prediction model
            actual-yield: actual-yield,
            quality-grade: quality-grade,
            harvest-timestamp: stacks-block-height,
            market-price: market-price,
            total-revenue: total-revenue,
            insurance-impact: (/ (* (get payout-made policy) u100) (get coverage-amount policy))
        })
        
        (ok total-revenue)
    )
)

;; read only functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
    (map-get? crop-policies policy-id)
)

;; Get sensor data
(define-read-only (get-sensor-data (policy-id uint) (timestamp uint))
    (map-get? sensor-data {policy-id: policy-id, timestamp: timestamp})
)

;; Get weather event
(define-read-only (get-weather-event (event-id uint))
    (map-get? weather-events event-id)
)

;; Get external data
(define-read-only (get-external-data (policy-id uint) (data-type (string-ascii 20)) (timestamp uint))
    (map-get? external-data {policy-id: policy-id, data-type: data-type, timestamp: timestamp})
)

;; Get sustainability certification
(define-read-only (get-sustainability-cert (farmer principal) (cert-type uint))
    (map-get? sustainability-records {farmer: farmer, certification-type: cert-type})
)

;; Get yield data
(define-read-only (get-yield-data (policy-id uint) (season uint))
    (map-get? yield-data {policy-id: policy-id, season: season})
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    (ok {
        total-policies: (- (var-get next-policy-id) u1),
        total-claims: (- (var-get next-claim-id) u1),
        insurance-pool: (var-get total-insurance-pool),
        total-payouts: (var-get total-payouts-made),
        sustainability-bonus: (var-get sustainability-bonus-rate)
    })
)

;; Calculate premium with sustainability discount
(define-read-only (calculate-premium-with-discount
    (base-premium uint)
    (farmer principal)
    (field-size uint))
    (let (
        (organic-cert (map-get? sustainability-records {farmer: farmer, certification-type: CERT-ORGANIC}))
        (carbon-cert (map-get? sustainability-records {farmer: farmer, certification-type: CERT-CARBON-NEUTRAL}))
        (water-cert (map-get? sustainability-records {farmer: farmer, certification-type: CERT-WATER-EFFICIENT}))
        (bio-cert (map-get? sustainability-records {farmer: farmer, certification-type: CERT-BIODIVERSITY}))
        (discount-percentage (+ 
            (if (is-some organic-cert) u5 u0)
            (if (is-some carbon-cert) u5 u0)
            (if (is-some water-cert) u3 u0)
            (if (is-some bio-cert) u2 u0)
        ))
        (discounted-premium (- base-premium (/ (* base-premium discount-percentage) u100)))
    )
        (ok (* discounted-premium field-size))
    )
)

;; private functions

;; Check for automatic payout triggers
(define-private (check-payout-triggers (policy-id uint))
    (let (
        (latest-sensor (map-get? sensor-data {policy-id: policy-id, timestamp: stacks-block-height}))
    )
        (match latest-sensor
            sensor-reading
                (begin
                    ;; Check drought conditions
                    (if (< (get soil-moisture sensor-reading) u20)
                        (create-weather-event policy-id EVENT-DROUGHT u7)
                        false
                    )
                    ;; Check flood conditions  
                    (if (> (get rainfall sensor-reading) FLOOD-THRESHOLD)
                        (create-weather-event policy-id EVENT-FLOOD u8)
                        false
                    )
                    ;; Check temperature extremes
                    (if (> (get air-temperature sensor-reading) TEMP-HIGH-THRESHOLD)
                        (create-weather-event policy-id EVENT-FROST u6)
                        false
                    )
                    ;; Check wind damage
                    (if (> (get wind-speed sensor-reading) WIND-THRESHOLD)
                        (create-weather-event policy-id EVENT-WIND u7)
                        false
                    )
                )
            false
        )
    )
)

;; Create weather event record
(define-private (create-weather-event (policy-id uint) (event-type uint) (severity uint))
    (let (
        (event-id (var-get next-claim-id))
    )
        (map-set weather-events event-id {
            policy-id: policy-id,
            event-type: event-type,
            severity: severity,
            start-timestamp: stacks-block-height,
            end-timestamp: u0,
            verified-loss: false,
            payout-triggered: false,
            payout-amount: u0,
            data-sources: (list "iot-sensor")
        })
        true
    )
)

