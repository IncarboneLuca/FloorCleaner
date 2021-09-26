;******************************************
;*             FLOORCLEANER               *
;*           by Luca Incarbone            *
;*  versione 1.3                          *
;*                 last change 15/03/2007 *
;*                  Politecnico di Torino *
;******************************************

;-Come la versione 1.2 ha una modalità di navigazione
; diversa dallo scanning, questa è selezionabile dall'utente tramite un deviatore
; che collega tramite una resistenza massa o VAL al PD2
; L'utente quindi potra selezionare una delle due modalità, e accendere l'apparecchio
; combinare le due modalità puo fornire migliori risultati di pulizia.
;-Introduce un nuovo sensore laterale che evita di rimanere incarstrato in un angolo 
; con la modalità MOVING, sensore che non viene usato in altro modo.

.NOLIST

.INCLUDE "atmega8.inc"

.LIST
; la direttiva .NOLIST and .LIST esclude/include dal listato il contenuto dei file
; compreso tra queste due direttive
; (In particolare il file 'atmega8.inc' non sarà incluso nel file AVR_BLINK.LST
; generato durante la compilazione).
; La direttiva .INCLUDE serve per inserire un file nella posizione in cui la direttiva
; appare. In genere viene utilizzata per includere parti del sorgente relative
; alla definizione di costanti, macro, etc..
; Un utilizzo, in genere, è quello di inserire le definizioni dei riferimenti
; ai registri ed ai bit di un particolare microcontrollore.
; In questo caso è stato incluso il file 'atmega8.inc' relativo al microcontrollore
; ATmega8L utilizzato per eseguire questo programma.
; Possono esistere inclusioni nidificate.

; Definizione dei registri utilizzati
.DEF    mp = R16
.DEF    n1 = R17
.DEF    n2 = R18
.DEF    n3 = R19
.DEF    stato = R20 ;nelle due funzionalità viene usato in modo diverso

rjmp main

main:
; In questo punto inizia la routine principale del programma, che deve
; essere un 'loop' chiuso, o  terminare con un 'loop' infinito. 
; Il listato assembler è costituito, in generale da una prima etichetta
; o 'label' seguita da ':' e seguita dal codice 'mnemonico' dell'istruzione
; da eseguire. Tale etichetta definisce un nome relativo ad una posizione 
; di programma (indirizzo) per tutte le istruzioni che necessitano di 
; un riferimento ad una particolare zona di programma, ad esempio le 
; istruzioni di salto o chiamata a procedura.
	

    ldi     mp,0x02
    out     SPH,mp
    ldi     mp,0x5f
    out     SPL,mp

	ldi mp,0b00001111 ;uscite motori 0000ADXX per il SX e 0000XXDA per il DX
	out DDRC,mp       ;interni sono di retromarcia ed esterni di avanzamento

	ldi mp,0b00001110;uscite per il controllo dei due mosfet per alimentare i sensori ottici
	;in PB1 e PB2 
	out DDRB,mp
	ldi mp,0b000000110 ;i MOS dei sensori ottici inizialmente li tengo disattivati
	out PORTB,mp

	ldi mp,0b00000000
	out DDRD,mp ;configuro il PD6 e PD7 come AIN! e AIN0 in PD6 e PD7
	; mentre PD0 e PD1 ingressi ai sensori di contatto con relative resistenze di PULL UP
	; a PD2 collego una resitenza di PULL UP con un interruttore (mi servirà per decidere la
	; modalità di navigazione)
	ldi mp,0b11000111
	out PORTD,mp
	nop
	ldi stato,0xff
	nop
	in mp,PIND
	nop
	sbrc mp,2 ;verifica se la resistenza di PULL UP è connessa ad alimentazione 
		rjmp moving ; se vale uno (RPULLUP connessa a VAL) si muove in modalità MOVING
	;se la resitenza non è collegata a VAL ma a massa allora si muove in modalità SCANNING

;Modalità di movimento SCANNING
;Questa modalità di movimento prevede l'incontro di uno ostacolo, la rotazione(con mezzo passo)
;di 180° e la ricerca di un'altro ostacolo, ideale per grandi superfici con pochi ostacoli
pulizia: ;ciclo che rifà infinite volte per pulire l'intera zona

	rcall avanti
	rcall scan
	rcall inversioneDX
HalfClean:  ;indirizzo che servirà per entrare nel ciclo ma non dall'inizio (vedi NFZsx)
	rcall avanti
	rcall scan
	rcall inversioneSX

rjmp pulizia

;Modalità di movimento MOVING
; Questa modalità prevede l'incontro con un ostacolo, rotazione fino a strada libera
;e avanzamento. Questo fa si che arrivato contro una parete si ruota fino ad essere parallelo 
;a questa, e procedendo avanti pulisce lungo i bordi del pavimento.
; Nel caso di ostacoli e ambienti complessi diventa un buon modo per districarsi nei labirinti
;casalinghi.
moving:
	
	rcall avanti
	rcall scan_contact
	rcall STOP
	rcall rotation ;ruota fino a che i sensori, anche quelli ottici non danno segnale di percorso libero
	dec stato     ; in questo modo n cicli li fa in logica di movimento, se si dovesse "incastrare farebbe 
					;una rotazione che lo disincastrerebbe
	brne    moving ; torna a moving per n volte
	ldi stato,0xaf ; riinizializzo il registro stato cosi al ciclo successivo riinizia il conto alla rovescia
	ldi mp,0b00000010
	out PORTC,mp 
	rcall delayHS 	; per sbloccarlo da una eventuale situazione di incastro
	ldi mp,0b00000000
	out PORTC,mp 

rjmp moving
Half_move_cicle:
	ldi stato,0xa0
	rcall avanti
	rcall scan_contact
	rcall STOP
	rcall rotation_opp
	dec stato         ; lo stato serve a conteggiare i tocchi, se troppi (tipo incastro) si leva
	brne Half_move_cicle
	ldi stato,0xff
	rcall giraSX

rjmp moving

; Funzioni per SCANNING-MODE & MOVING-MODE
;------------------------------------------
;Per fare andare avanti entrambi i motori 
;Le due uscite sono ovviamente collegate a dei MOS che pilotano i motori fornendo la corrente adeguata
avanti:
	ldi mp,0b00001001
	out PORTC,mp ;Accende cosi i due motorini
ret

;Accende i fotodiodi e "vede" se è arrivato vicino a un ostacolo
;se arriva alla soglia prestabilita allora richiama la funzione STOP che 
;ferma la macchina, controlla inoltre i sensori di contatto
; non esce finche non trova ostacoli
;
;Per prima cosa verifica se i sensori di contatto danno segno positivo, questi se non stimolati 
;portano a 'zero' PD0 e PD1. se stimolati tramite una resistenza di PULLUP portano i 5V in ingresso.
;Poi attivo il compartore di soglia, attivo uno dei sensori ottici, verifico, disttivo il sensore,
;attivo l'altro e via dicendo. 
scan:
	in mp,PIND
	nop
	sbrc mp,0
		rjmp end_scan ;in questo modo scansiona i sensori di contatto
	sbrc mp,1
		rjmp end_scan
	ldi mp,(0<<ACME)
	out SFIOR,mp
	ldi mp,0x00 ;(0<<ACD)
	out ACSR,mp;to turn on the COMPARATOR		
		ldi mp,0b00000100 ;mando in conduzione il primo sensore ponendolo a 0
		out PORTB,mp
		rcall wait
		in mp,ACSR
		sbrc mp,ACO
			rjmp end_scan
		ldi mp,0b00000110 ; disattivo entrambi i MOS un attimo prima di attivare il secondo
		; di modo da evitare l'attivazione seppur momentanea di entrambi.
		nop		nop		nop
		ldi mp,0b0000010 ; mando cosi in conduzione il secondo MOS
		out PORTB,mp
		rcall wait
		in  mp,ACSR
		sbrs mp,ACO
			rjmp scan
		
	end_scan:
		rcall STOP
		ldi mp,0b00000110  ;disattivo i sensori ottici
		out PORTB,mp
	ldi mp,(1<<ACD)|(1<<ACIE)
	out ACSR,mp;to turn off the COMPARATOR
	
ret





;Simile allo scan, però NON continua a controllare le entrate finche non risultino positive
;se non vede ostacoli semplicemente lo segnala. Per segnalarlo uso il registro 'stato' impostando
; il 7° bit a uno. Quindi lo setto soltanto se i sensori vedono qualcosa
;interroga soltanto i sensori di contatto.
look:
	ldi stato,0x00 ;azzero il registro stato
	in mp,PIND
	nop
	sbrc mp,0
		rjmp end_look ;in questo modo controlla i sensori di contatto
	sbrc mp,1
		rjmp end_look ;il secondo sensore di contatto
	
			
	ret  ; se non ha visto l'ostacolo ritorna subito alla funzione di partenza
	
	end_look:
		rcall STOP
	ldi stato,0xff ;segnala che è a contatto con un ostacolo
ret

;Trovando un ostacolo si gira di 90 gradi, avanza di un "passo" 
;controlla che sia libero, avanza di un secondo "passo" e gira di 90 gradi
;il risultato finale è di una rotazione di 180gradi con uno spostamento 
;laterale che gli permetterà di pulire un'altra striscia di pavimento
inversioneDX:

	rcall giraDX
	rcall HalfStep
	rcall look
	
		sbrc stato,7
				rjmp NFZdx ; to function NextFreeZone
	end_if:
	rcall HalfStep
	rcall giraDX
	rcall STOP
ret

; Del tutto simile a inversione dx cambiano le rotazioni, la dx e la sx si alternano, per
; fare una "scannerizzazione" del pavimento adeguata.
inversioneSX:
	rcall giraSX
	rcall HalfStep
	rcall look ;guarda se ci sono ostacoli, e se ci sono il seguente elenco di 
	;skeep branch if interpreta quello che la sottofunzione look ha trovato,
	;nel caso in cui ci sia un ostacolo salta a una funzione per cercare la next free zone
		
		sbrc stato,7
				rjmp NFZsx ; to function NextFreeZone
	if_end:
	rcall HalfStep
	rcall giraSX
	rcall STOP
ret

;Cerca avanzando lungo l'ostacolo in caerca di nuove zone da pulire, una volta
;trovata inizia il ciclo dall'inizio in modo che quando si presenta un nuovo ostacolo girerà a sx

NFZdx:
 	rcall giraDX
	rcall HalfStep
	;Controlla che non sia arrivato dall'altra parte della parete, e se lo fosse deve riprendere un'altro ciclo.
		rcall look ; se davanti c'è un ostacolo allora riparte da HalfClean
		sbrc stato,7
				rcall giraSX ;se c'è un ostacolo si gira

		sbrc stato,7
				rjmp HalfClean ;e poi riprende da metà ciclo pulizia
		
		


	ldi mp,0b00000001
	out PORTC,mp 		;giraDX avanti
	rcall delayROT
	ldi mp,0b00001001
	out PORTC,mp
	rcall wait
	ldi mp,0b00000000
	out PORTC,mp
	;ora controlla se c'è un ostacolo
	rcall look
	;se l'ha trovato
	;nel caso in cui ci sia un ostacolo salta a una funzione per cercare la next free zone
		sbrc stato,7
				rjmp NFZdx ;se c'è un ostacolo continua la ricerca
		

	rjmp pulizia
;end NextFreeZone_dx


;Cerca avanzando lungo l'ostacolo in caerca di nuove zone da pulire, una volta
;trovata inizia il ciclo da metà, in modo che quando si presenta un nuovo ostacolo girerà a dx

NFZsx:
 	rcall giraSX
	rcall HalfStep
	;Controlla che non sia arrivato dall'altra parte della parete, e se lo fosse deve riprendere un'altro ciclo.
		rcall look ; se davanti c'è un ostacolo allora riparte dall'inizio della pulizia
		sbrc stato,7
				rcall giraDX ;se c'è un ostacolo si gira
		sbrc stato,7
				rjmp pulizia ;e poi  riprende dall'inizio del ciclo di pulizia
		Notfoward:
	ldi mp,0b00001000
	out PORTC,mp 		;giraSX avanti
	rcall delayROT
	ldi mp,0b00001001
	out PORTC,mp
	rcall wait
	ldi mp,0b00000000
	out PORTC,mp
	;ora controlla se c'è un ostacolo
	rcall look
	;se l'ha trovato
	;nel caso in cui ci sia un ostacolo salta a una funzione per cercare la next free zone

		sbrc stato,7
				rjmp NFZsx ;
		NotFound:
	
	rjmp HalfClean
;end NextFreeZone_sx

;Funzione che fa fare un "passo avanti" al FloorCleaner, utile per le inversioni e per i NextFreeZone
HalfStep:
	ldi mp,0b00001001 ;HALFSTEP
	out PORTC,mp
	rcall delayHS
	ldi mp,0b00000000
	out PORTC,mp		
ret

;Funzione per fermare i motorini
STOP:
	ldi mp,0x00
	out PORTC,mp
ret

;Funzione per girare a dx di 90° tramite rotazione inversa della ruota dx
giraDX:
	ldi mp,0b00000010
	out PORTC,mp 	
	rcall delayROT	;giraDX
	ldi mp,0x00
	out PORTC,mp
ret

;Funzione per girare a sx di 90° tramite rotazione inversa della ruota sx
giraSX:
	ldi mp,0b00000100
	out PORTC,mp 
	rcall delayROT	;rotaz SX
	ldi mp,0x00
	out PORTC,mp
ret

; Delay corretto sperimentalmente per ottenere una rotazione del FloorCleaner di 90Gradi
delayROT:
	ldi     n3,0x14

delay_loop3:
    ldi     n2,0xff

delay_loop2:
    ldi     n1,0xff

delay_loop1:
    dec     n1
    brne    delay_loop1
    dec     n2
    brne    delay_loop2
    dec     n3
    brne    delay_loop3
	ldi n3,0xb0
	adjust:
	dec n3
	brne adjust

ret

;Delay provato sperimentalmente per ottenere un movimento pari alla larghezza del FloorCleaner
delayHS:

	ldi     n3,0x09

delay_loopHS3:
    ldi     n2,0xff

delay_loopHS2:
    ldi     n1,0xff

delay_loopHS1:
    dec     n1
    brne    delay_loopHS1
    dec     n2
    brne    delay_loopHS2
    dec     n3
    brne    delay_loopHS3
	

ret

;Funzione che mi è utile per aspettare che i sensori, e l'uscita del comparatore di soglia
;entrino in funzione correttamente
wait:
	nop		nop		nop		nop		nop		nop		nop		nop		nop		nop
	nop     nop		nop		nop		nop		nop		nop	    nop     nop     nop

ret

;Ora le funzioni che vengono utilizzate solo da MOVING-MODE
;-----------------------------------------------------------

;Funzione che controlla soltanto il sensore di contatto Non viene mai usata in SCANNING MODE
scan_contact:

	ldi     n3,0x05
delay_loopSC3:
    ldi     n2,0xff
delay_loopSC2:
    ldi     n1,0xff
delay_loopSC1:

	in mp,PIND ;in questo modo all'interno del ciclo di conteggio verifica i sensori
	nop
	sbrc mp,0
		rjmp end_scan_contact ;in questo modo scansiona i sensori di contatto	sbrc mp,1
	sbrc mp,1
		rjmp end_scan_contact
	
	
    dec     n1
    brne    delay_loopSC1
    dec     n2
    brne    delay_loopSC2
    dec     n3
    brne    delay_loopSC3
	
	in mp,PIND ;in questo modo all'interno del ciclo di conteggio verifica i sensori
	nop
	sbrc mp,0
		rjmp end_scan_contact ;in questo modo scansiona i sensori di contatto
	sbrc mp,1
		rjmp end_scan_contact
	rjmp moving
end_scan_contact:
ret

rotation:
		;valuta se uno dei due lati è vicino all'oggetto toccato, se è vicino gira in
		; modo da fiancheggiarlo, in caso contrario gira dal lato opposto ma senza controllare 
		; che l'oggetto sia dal lato opposto fornendo così una soluzione al caso 'non vedo nulla'
	ldi mp,(0<<ACME)
	out SFIOR,mp
	ldi mp,0x00 ;(0<<ACD)
	out ACSR,mp;to turn on the COMPARATOR		
		ldi mp,0b00000100 ;mando in conduzione il primo sensore ponendolo a 0
		out PORTB,mp
		rcall wait
		in mp,ACSR
		sbrc mp,ACO
			rcall check_laterale
		ldi mp,0b00000010
		ldi n1,0b00000010 ;memorizzo temporaneamente
		out PORTC,mp 	
		;GITRA SX
		
		rjmp end_valutazione_lato
	giro_opposto:
		ldi mp,(1<<ACD)|(1<<ACIE); nella funzione check era rimasto acceso
		out ACSR,mp;to turn off the COMPARATOR
		ldi mp,0b00000000 ;disattivo il sensore laterale
		out PORTB,mp
		ldi mp,0b00000100
		ldi n1,0b00000100;memorizzo temporaneamente
		out PORTC,mp 	
		;GITRA DX
	 
		
	end_valutazione_lato:
	;dopo aver stabilito il lato inizia la rotazione
		in mp,PIND
		nop
		sbrc mp,0
			rjmp end_valutazione_lato
		sbrc mp,1
			rjmp end_valutazione_lato
			ldi mp,(0<<ACME)
	
		out SFIOR,mp
		ldi mp,0x00 ;(0<<ACD)
		out ACSR,mp;to turn on the COMPARATOR		
			ldi mp,0b00000100 ;mando in conduzione il primo sensore ponendolo a 0
			out PORTB,mp
			rcall wait
			in mp,ACSR
			sbrc mp,ACO
				rjmp end_valutazione_lato
		ldi mp,0b00000110 ; disattivo entrambi i MOS un attimo prima di attivare il secondo
		; di modo da evitare l'attivazione seppur momentanea di entrambi.
		out PORTB,mp
		nop		nop		nop
		ldi mp,0b00000010 ; mando cosi in conduzione il secondo MOS
		out PORTB,mp
		rcall wait
		in  mp,ACSR
		sbrc mp,ACO
			rjmp end_valutazione_lato
		
		ldi mp,0b00000110  ;disattivo i sensori ottici
		out PORTB,mp
	ldi mp,(1<<ACD)|(1<<ACIE)
	out ACSR,mp;to turn off the COMPARATOR
	rcall wait

	sbrc n1,2 ;se ho girato inverso allora lo faccio continuare a girare inversmente per un certo numero di contatti
		rjmp Half_move_cicle

ret


;Questa funzione viene chiamata prima di girare a dx (giro opposto) in modalità moving 
;in modo che se c'è un ostacolo che bloccherebbe la rotazione stessa viene cambiato 
;il lato di rotazione ritornando su giro normale
check_laterale:
    ldi mp,0b000000110 ;i MOS dei sensori ottici frontali li tengo disattivati
	out PORTB,mp
    ldi mp,(0<<ACME)
	out SFIOR,mp
	ldi mp,0x00 ;(0<<ACD)
	out ACSR,mp;to turn on the COMPARATOR		
		ldi mp,0b00001110 ;mando in conduzione il MOS del sensore laterale
		out PORTB,mp
		rcall wait
		in mp,ACSR
	sbrs mp,ACO
		rjmp giro_opposto
ret


rotation_opp:

		ldi mp,0b0000101
		out PORTC,mp 	
		;GITRA DX
		
	ciclo_rotazione_opp:
	;dopo aver stabilito il lato inizia la rotazione
		in mp,PIND
		rcall wait
		
	
		sbrc mp,0
			rjmp ciclo_rotazione_opp
		sbrc mp,1
			rjmp ciclo_rotazione_opp
		ldi mp,(0<<ACME)
		out SFIOR,mp
		ldi mp,0x00 ;(0<<ACD)
		out ACSR,mp;to turn on the COMPARATOR		
			ldi mp,0b00000100 ;mando in conduzione il primo sensore ponendolo a 0
			out PORTB,mp
			rcall wait
			in mp,ACSR
			sbrc mp,ACO
				rjmp ciclo_rotazione_opp
		ldi mp,0b00000110 ; disattivo entrambi i MOS un attimo prima di attivare il secondo
		; di modo da evitare l'attivazione seppur momentanea di entrambi.
		out PORTB,mp
		nop		nop		nop
		ldi mp,0b00000010 ; mando cosi in conduzione il secondo MOS
		out PORTB,mp
		rcall wait
		in  mp,ACSR
		sbrc mp,ACO
			rjmp ciclo_rotazione_opp
		
		ldi mp,0b00000110  ;disattivo i sensori ottici
		out PORTB,mp
	ldi mp,(1<<ACD)|(1<<ACIE)
	out ACSR,mp;to turn off the COMPARATOR
	rcall wait
ret
