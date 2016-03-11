#= require ./BANNER

umd = (factory) ->
  if typeof exports is 'object'
    module.exports = factory()
  else if typeof define is 'function' and define.amd
    define([], factory)
  else
    @Turbolinks = factory()

umd ->
  Turbolinks =
    supported: do ->
      window.history.pushState? and window.requestAnimationFrame?

    visit: (location, options) ->
      Turbolinks.controller.visit(location, options)

    clearCache: ->
      Turbolinks.controller.clearCache()

  Turbolinks.copyObject = (object) ->
    result = {}
    for key, value of object
      result[key] = value
    result

  Turbolinks.closest = (element, selector) ->
    closest.call(element, selector)

  closest = do ->
    html = document.documentElement
    html.closest ? (selector) ->
      node = this
      while node
        return node if node.nodeType is Node.ELEMENT_NODE and match.call(node, selector)
        node = node.parentNode


  Turbolinks.defer = (callback) ->
    setTimeout(callback, 1)


  Turbolinks.dispatch = (eventName, {target, cancelable, data} = {}) ->
    event = document.createEvent("Events")
    event.initEvent(eventName, true, cancelable is true)
    event.data = data ? {}
    (target ? document).dispatchEvent(event)
    event


  Turbolinks.match = (element, selector) ->
    match.call(element, selector)

  match = do ->
    html = document.documentElement
    html.matchesSelector ? html.webkitMatchesSelector ? html.msMatchesSelector ? html.mozMatchesSelector


  Turbolinks.uuid = ->
    result = ""
    for i in [1..36]
      if i in [9, 14, 19, 24]
        result += "-"
      else if i is 15
        result += "4"
      else if i is 20
        result += (Math.floor(Math.random() * 4) + 8).toString(16)
      else
        result += Math.floor(Math.random() * 15).toString(16)
    result

  class Turbolinks.Location
    @wrap: (value) ->
      if value instanceof this
        value
      else
        new this value

    constructor: (url = "") ->
      linkWithAnchor = document.createElement("a")
      linkWithAnchor.href = url.toString()

      @absoluteURL = linkWithAnchor.href

      anchorLength = linkWithAnchor.hash.length
      if anchorLength < 2
        @requestURL = @absoluteURL
      else
        @requestURL = @absoluteURL.slice(0, -anchorLength)
        @anchor = linkWithAnchor.hash.slice(1)

    getOrigin: ->
      @absoluteURL.split("/", 3).join("/")

    getPath: ->
      @absoluteURL.match(/\/\/[^/]*(\/[^?;]*)/)?[1] ? "/"

    getPathComponents: ->
      @getPath().split("/").slice(1)

    getLastPathComponent: ->
      @getPathComponents().slice(-1)[0]

    getExtension: ->
      @getLastPathComponent().match(/\.[^.]*$/)?[0]

    isHTML: ->
      extension = @getExtension()
      extension is ".html" or not extension?

    isPrefixedBy: (location) ->
      prefixURL = getPrefixURL(location)
      @isEqualTo(location) or stringStartsWith(@absoluteURL, prefixURL)

    isEqualTo: (location) ->
      @absoluteURL is location?.absoluteURL

    toCacheKey: ->
      @requestURL

    toJSON: ->
      @absoluteURL

    toString: ->
      @absoluteURL

    valueOf: ->
      @absoluteURL

    # Private

    getPrefixURL = (location) ->
      addTrailingSlash(location.getOrigin() + location.getPath())

    addTrailingSlash = (url) ->
      if stringEndsWith(url, "/") then url else url + "/"

    stringStartsWith = (string, prefix) ->
      string.slice(0, prefix.length) is prefix

    stringEndsWith = (string, suffix) ->
      string.slice(-suffix.length) is suffix

  class Turbolinks.HttpRequest
    @NETWORK_FAILURE = 0
    @TIMEOUT_FAILURE = -1

    @timeout = 60

    constructor: (@delegate, location, referrer) ->
      @url = Turbolinks.Location.wrap(location).requestURL
      @referrer = Turbolinks.Location.wrap(referrer).absoluteURL
      @createXHR()

    send: ->
      if @xhr and not @sent
        @notifyApplicationBeforeRequestStart()
        @setProgress(0)
        @xhr.send()
        @sent = true
        @delegate.requestStarted?()

    cancel: ->
      if @xhr and @sent
        @xhr.abort()

    # XMLHttpRequest events

    requestProgressed: (event) =>
      if event.lengthComputable
        @setProgress(event.loaded / event.total)

    requestLoaded: =>
      @endRequest =>
        if 200 <= @xhr.status < 300
          @delegate.requestCompletedWithResponse(@xhr.responseText, @xhr.getResponseHeader("Turbolinks-Location"))
        else
          @failed = true
          @delegate.requestFailedWithStatusCode(@xhr.status, @xhr.responseText)

    requestFailed: =>
      @endRequest =>
        @failed = true
        @delegate.requestFailedWithStatusCode(@constructor.NETWORK_FAILURE)

    requestTimedOut: =>
      @endRequest =>
        @failed = true
        @delegate.requestFailedWithStatusCode(@constructor.TIMEOUT_FAILURE)

    requestCanceled: =>
      @endRequest()


    # Application events

    notifyApplicationBeforeRequestStart: ->
      Turbolinks.dispatch("turbolinks:request-start", data: { url: @url, xhr: @xhr })

    notifyApplicationAfterRequestEnd: ->
      Turbolinks.dispatch("turbolinks:request-end", data: { url: @url, xhr: @xhr })

    # Private

    createXHR: ->
      @xhr = new XMLHttpRequest
      @xhr.open("GET", @url, true)
      @xhr.timeout = @constructor.timeout * 1000
      @xhr.setRequestHeader("Accept", "text/html, application/xhtml+xml")
      @xhr.setRequestHeader("Turbolinks-Referrer", @referrer)
      @xhr.onprogress = @requestProgressed
      @xhr.onload = @requestLoaded
      @xhr.onerror = @requestFailed
      @xhr.ontimeout = @requestTimedOut
      @xhr.onabort = @requestCanceled

    endRequest: (callback) ->
      if @xhr
        @notifyApplicationAfterRequestEnd()
        callback?.call(this)
        @destroy()

    setProgress: (progress) ->
      @progress = progress
      @delegate.requestProgressed?(@progress)

    destroy: ->
      @setProgress(1)
      @delegate.requestFinished?()
      @delegate = null
      @xhr = null

  class Turbolinks.ProgressBar
    ANIMATION_DURATION = 300

    @defaultCSS: """
      .turbolinks-progress-bar {
        position: fixed;
        display: block;
        top: 0;
        left: 0;
        height: 3px;
        background: #0076ff;
        z-index: 9999;
        transition: width #{ANIMATION_DURATION}ms ease-out, opacity #{ANIMATION_DURATION / 2}ms #{ANIMATION_DURATION / 2}ms ease-in;
        transform: translate3d(0, 0, 0);
      }
    """

    constructor: ->
      @stylesheetElement = @createStylesheetElement()
      @progressElement = @createProgressElement()

    show: ->
      unless @visible
        @visible = true
        @installStylesheetElement()
        @installProgressElement()
        @startTrickling()

    hide: ->
      if @visible and not @hiding
        @hiding = true
        @fadeProgressElement =>
          @uninstallProgressElement()
          @stopTrickling()
          @visible = false
          @hiding = false

    setValue: (@value) ->
      @refresh()

    # Private

    installStylesheetElement: ->
      document.head.insertBefore(@stylesheetElement, document.head.firstChild)

    installProgressElement: ->
      @progressElement.style.width = 0
      @progressElement.style.opacity = 1
      document.documentElement.insertBefore(@progressElement, document.body)
      @refresh()

    fadeProgressElement: (callback) ->
      @progressElement.style.opacity = 0
      setTimeout(callback, ANIMATION_DURATION * 1.5)

    uninstallProgressElement: ->
      if @progressElement.parentNode
        document.documentElement.removeChild(@progressElement)

    startTrickling: ->
      @trickleInterval ?= setInterval(@trickle, ANIMATION_DURATION)

    stopTrickling: ->
      clearInterval(@trickleInterval)
      @trickleInterval = null

    trickle: =>
      @setValue(@value + Math.random() / 100)

    refresh: ->
      requestAnimationFrame =>
        @progressElement.style.width = "#{10 + (@value * 90)}%"

    createStylesheetElement: ->
      element = document.createElement("style")
      element.type = "text/css"
      element.textContent = @constructor.defaultCSS
      element

    createProgressElement: ->
      element = document.createElement("div")
      element.classList.add("turbolinks-progress-bar")
      element


  class Turbolinks.BrowserAdapter
    {NETWORK_FAILURE, TIMEOUT_FAILURE} = Turbolinks.HttpRequest
    PROGRESS_BAR_DELAY = 500

    constructor: (@controller) ->
      @progressBar = new Turbolinks.ProgressBar

    visitProposedToLocationWithAction: (location, action) ->
      @controller.startVisitToLocationWithAction(location, action)

    visitStarted: (visit) ->
      visit.changeHistory()
      visit.issueRequest()
      visit.loadCachedSnapshot()

    visitRequestStarted: (visit) ->
      @progressBar.setValue(0)
      if visit.hasCachedSnapshot() or visit.action isnt "restore"
        @showProgressBarAfterDelay()
      else
        @showProgressBar()

    visitRequestProgressed: (visit) ->
      @progressBar.setValue(visit.progress)

    visitRequestCompleted: (visit) ->
      visit.loadResponse()

    visitRequestFailedWithStatusCode: (visit, statusCode) ->
      switch statusCode
        when NETWORK_FAILURE, TIMEOUT_FAILURE
          @reload()
        else
          visit.loadResponse()

    visitRequestFinished: (visit) ->
      @hideProgressBar()

    visitCompleted: (visit) ->
      visit.followRedirect()

    pageInvalidated: ->
      @reload()

    # Private

    showProgressBarAfterDelay: ->
      @progressBarTimeout = setTimeout(@showProgressBar, PROGRESS_BAR_DELAY)

    showProgressBar: =>
      @progressBar.show()

    hideProgressBar: ->
      @progressBar.hide()
      clearTimeout(@progressBarTimeout)

    reload: ->
      window.location.reload()

  pageLoaded = false

  addEventListener "load", ->
    Turbolinks.defer ->
      pageLoaded = true
  , false

  class Turbolinks.History
    constructor: (@delegate) ->

    start: ->
      unless @started
        addEventListener("popstate", @onPopState, false)
        @started = true

    stop: ->
      if @started
        removeEventListener("popstate", @onPopState, false)
        @started = false

    push: (location, restorationIdentifier) ->
      location = Turbolinks.Location.wrap(location)
      @update("push", location, restorationIdentifier)

    replace: (location, restorationIdentifier) ->
      location = Turbolinks.Location.wrap(location)
      @update("replace", location, restorationIdentifier)

    # Event handlers

    onPopState: (event) =>
      if @shouldHandlePopState()
        if turbolinks = event.state?.turbolinks
          location = Turbolinks.Location.wrap(window.location)
          restorationIdentifier = turbolinks.restorationIdentifier
          @delegate.historyPoppedToLocationWithRestorationIdentifier(location, restorationIdentifier)

    # Private

    shouldHandlePopState: ->
      # Safari dispatches a popstate event after window's load event, ignore it
      pageLoaded is true

    update: (method, location, restorationIdentifier) ->
      state = turbolinks: {restorationIdentifier}
      history[method + "State"](state, null, location)

  class Turbolinks.ElementSet
    constructor: (elements) ->
      @elements = for element in elements when element.nodeType is Node.ELEMENT_NODE
        element: element
        value: element.outerHTML

    selectElementsMatchingSelector: (selector) ->
      elements = (element for {element, value} in @elements when Turbolinks.match(element, selector))
      new @constructor elements

    getElementsNotPresentInSet: (elementSet) ->
      index = elementSet.getElementIndex()
      elements = (element for {element, value} in @elements when value not of index)
      new @constructor elements

    getElements: ->
      element for {element} in @elements

    getValues: ->
      value for {value} in @elements

    isEqualTo: (elementSet) ->
      @toString() is elementSet?.toString()

    toString: ->
      @getValues().join("")

    # Private

    getElementIndex: ->
      @elementIndex ?= (
        elementIndex = {}
        for {element, value} in @elements
          elementIndex[value] = element
        elementIndex
      )


  class Turbolinks.Snapshot
    @wrap: (value) ->
      if value instanceof this
        value
      else
        @fromHTML(value)

    @fromHTML: (html) ->
      element = document.createElement("html")
      element.innerHTML = html
      @fromElement(element)

    @fromElement: (element) ->
      new this
        head: element.querySelector("head")
        body: element.querySelector("body")

    constructor: ({head, body}) ->
      @head = head ? document.createElement("head")
      @body = body ? document.createElement("body")

    getRootLocation: ->
      root = @getSetting("root") ? "/"
      new Turbolinks.Location root

    getCacheControlValue: ->
      @getSetting("cache-control")

    hasAnchor: (anchor) ->
      @body.querySelector("##{anchor}")?

    hasSameTrackedHeadElementsAsSnapshot: (snapshot) ->
      @getTrackedHeadElementSet().isEqualTo(snapshot.getTrackedHeadElementSet())

    getInlineHeadElementsNotPresentInSnapshot: (snapshot) ->
      inlineStyleElements = @getInlineHeadStyleElementSet().getElementsNotPresentInSet(snapshot.getInlineHeadStyleElementSet())
      inlineScriptElements = @getInlineHeadScriptElementSet().getElementsNotPresentInSet(snapshot.getInlineHeadScriptElementSet())
      inlineStyleElements.getElements().concat(inlineScriptElements.getElements())

    getTemporaryHeadElements: ->
      @getTemporaryHeadElementSet().getElements()

    isPreviewable: ->
      @getCacheControlValue() isnt "no-preview"

    # Private

    getSetting: (name) ->
      [..., element] = @head.querySelectorAll("meta[name='turbolinks-#{name}']")
      element?.getAttribute("content")

    getTrackedHeadElementSet: ->
      @trackedHeadElementSet ?= @getPermanentHeadElementSet().selectElementsMatchingSelector("[data-turbolinks-track=reload]")

    getInlineHeadStyleElementSet: ->
      @inlineHeadStyleElementSet ?= @getPermanentHeadElementSet().selectElementsMatchingSelector("style")

    getInlineHeadScriptElementSet: ->
      @inlineHeadScriptElementSet ?= @getPermanentHeadElementSet().selectElementsMatchingSelector("script:not([src])")

    getPermanentHeadElementSet: ->
      @permanentHeadElementSet ?= @getHeadElementSet().selectElementsMatchingSelector("script, style, link[href], [data-turbolinks-track=reload]")

    getTemporaryHeadElementSet: ->
      @temporaryHeadElementSet ?= @getHeadElementSet().getElementsNotPresentInSet(@getPermanentHeadElementSet())

    getHeadElementSet: ->
      @headElementSet ?= new Turbolinks.ElementSet @head.childNodes


  class Turbolinks.View
    constructor: (@delegate) ->
      @element = document.documentElement

    getRootLocation: ->
      @getSnapshot().getRootLocation()

    getCacheControlValue: ->
      @getSnapshot().getCacheControlValue()

    getSnapshot: ({clone} = {clone: true}) ->
      element = if clone then @element.cloneNode(true) else @element
      Turbolinks.Snapshot.fromElement(element)

    render: ({snapshot, html, isPreview}, callback) ->
      @markAsPreview(isPreview)
      if snapshot?
        @renderSnapshot(Turbolinks.Snapshot.wrap(snapshot), callback)
      else
        @renderHTML(html, callback)

    # Private

    markAsPreview: (isPreview) ->
      if isPreview
        @element.setAttribute("data-turbolinks-preview", "")
      else
        @element.removeAttribute("data-turbolinks-preview")

    renderSnapshot: (newSnapshot, callback) ->
      currentSnapshot = @getSnapshot(clone: false)

      unless currentSnapshot.hasSameTrackedHeadElementsAsSnapshot(newSnapshot)
        @delegate.viewInvalidated()
        return false

      for element in newSnapshot.getInlineHeadElementsNotPresentInSnapshot(currentSnapshot)
        document.head.appendChild(element.cloneNode(true))

      for element in currentSnapshot.getTemporaryHeadElements()
        document.head.removeChild(element)

      for element in newSnapshot.getTemporaryHeadElements()
        document.head.appendChild(element.cloneNode(true))

      newBody = newSnapshot.body.cloneNode(true)
      @delegate.viewWillRender(newBody)

      importPermanentElementsIntoBody(newBody)
      document.body = newBody

      focusFirstAutofocusableElement()
      callback?()
      @delegate.viewRendered()

    renderHTML: (html, callback) ->
      document.documentElement.innerHTML = html
      activateScripts()
      callback?()
      @delegate.viewRendered()

    importPermanentElementsIntoBody = (newBody) ->
      for newChild in getPermanentElements(document.body)
        if oldChild = newBody.querySelector("[id='#{newChild.id}']")
          oldChild.parentNode.replaceChild(newChild, oldChild)

    getPermanentElements = (element) ->
      element.querySelectorAll("[id][data-turbolinks-permanent]")

    activateScripts = ->
      for oldChild in document.querySelectorAll("script")
        newChild = cloneScript(oldChild)
        oldChild.parentNode.replaceChild(newChild, oldChild)

    cloneScript = (script) ->
      element = document.createElement("script")
      if script.hasAttribute("src")
        element.src = script.getAttribute("src")
      else
        element.textContent = script.textContent
      element

    focusFirstAutofocusableElement = ->
      document.body.querySelector("[autofocus]")?.focus()

  class Turbolinks.ScrollManager
    constructor: (@delegate) ->

    start: ->
      unless @started
        addEventListener("scroll", @onScroll, false)
        @onScroll()
        @started = true

    stop: ->
      if @started
        removeEventListener("scroll", @onScroll, false)
        @started = false

    scrollToElement: (element) ->
      element.scrollIntoView()

    scrollToPosition: ({x, y}) ->
      window.scrollTo(x, y)

    onScroll: (event) =>
      @updatePosition(x: window.pageXOffset, y: window.pageYOffset)

    # Private

    updatePosition: (@position) ->
      @delegate?.scrollPositionChanged(@position)

  class Turbolinks.Cache
    constructor: (@size) ->
      @keys = []
      @snapshots = {}

    has: (location) ->
      key = keyForLocation(location)
      key of @snapshots

    get: (location) ->
      return unless @has(location)
      snapshot = @read(location)
      @touch(location)
      snapshot

    put: (location, snapshot) ->
      @write(location, snapshot)
      @touch(location)
      snapshot

    # Private

    read: (location) ->
      key = keyForLocation(location)
      @snapshots[key]

    write: (location, snapshot) ->
      key = keyForLocation(location)
      @snapshots[key] = snapshot

    touch: (location) ->
      key = keyForLocation(location)
      index = @keys.indexOf(key)
      @keys.splice(index, 1) if index > -1
      @keys.unshift(key)
      @trim()

    trim: ->
      for key in @keys.splice(@size)
        delete @snapshots[key]

    keyForLocation = (location) ->
      Turbolinks.Location.wrap(location).toCacheKey()

  class Turbolinks.Visit
    constructor: (@controller, location, @action) ->
      @identifier = Turbolinks.uuid()
      @location = Turbolinks.Location.wrap(location)
      @adapter = @controller.adapter
      @state = "initialized"
      @timingMetrics = {}

    start: ->
      if @state is "initialized"
        @recordTimingMetric("visitStart")
        @state = "started"
        @adapter.visitStarted(this)

    cancel: ->
      if @state is "started"
        @request?.cancel()
        @cancelRender()
        @state = "canceled"

    complete: ->
      if @state is "started"
        @recordTimingMetric("visitEnd")
        @state = "completed"
        @adapter.visitCompleted?(this)
        @controller.visitCompleted(this)

    fail: ->
      if @state is "started"
        @state = "failed"
        @adapter.visitFailed?(this)

    changeHistory: ->
      unless @historyChanged
        actionForHistory = if @location.isEqualTo(@referrer) then "replace" else @action
        method = getHistoryMethodForAction(actionForHistory)
        @controller[method](@location, @restorationIdentifier)
        @historyChanged = true

    issueRequest: ->
      if @shouldIssueRequest() and not @request?
        @progress = 0
        @request = new Turbolinks.HttpRequest this, @location, @referrer
        @request.send()

    getCachedSnapshot: ->
      if snapshot = @controller.getCachedSnapshotForLocation(@location)
        if not @location.anchor? or snapshot.hasAnchor(@location.anchor)
          if @action is "restore" or snapshot.isPreviewable()
            snapshot

    hasCachedSnapshot: ->
      @getCachedSnapshot()?

    loadCachedSnapshot: ->
      if snapshot = @getCachedSnapshot()
        isPreview = @shouldIssueRequest()
        @render ->
          @cacheSnapshot()
          @controller.render({snapshot, isPreview}, @performScroll)
          @adapter.visitRendered?(this)
          @complete() unless isPreview

    loadResponse: ->
      if @response?
        @render ->
          @cacheSnapshot()
          if @request.failed
            @controller.render(html: @response, @performScroll)
            @adapter.visitRendered?(this)
            @fail()
          else
            @controller.render(snapshot: @response, @performScroll)
            @adapter.visitRendered?(this)
            @complete()

    followRedirect: ->
      if @redirectedToLocation and not @followedRedirect
        @location = @redirectedToLocation
        @controller.replaceHistoryWithLocationAndRestorationIdentifier(@redirectedToLocation, @restorationIdentifier)
        @followedRedirect = true

    # HTTP Request delegate

    requestStarted: ->
      @recordTimingMetric("requestStart")
      @adapter.visitRequestStarted?(this)

    requestProgressed: (@progress) ->
      @adapter.visitRequestProgressed?(this)

    requestCompletedWithResponse: (@response, redirectedToLocation) ->
      @redirectedToLocation = Turbolinks.Location.wrap(redirectedToLocation) if redirectedToLocation?
      @adapter.visitRequestCompleted(this)

    requestFailedWithStatusCode: (statusCode, @response) ->
      @adapter.visitRequestFailedWithStatusCode(this, statusCode)

    requestFinished: ->
      @recordTimingMetric("requestEnd")
      @adapter.visitRequestFinished?(this)

    # Scrolling

    performScroll: =>
      unless @scrolled
        if @action is "restore"
          @scrollToRestoredPosition() or @scrollToTop()
        else
          @scrollToAnchor() or @scrollToTop()
        @scrolled = true

    scrollToRestoredPosition: ->
      position = @restorationData?.scrollPosition
      if position?
        @controller.scrollToPosition(position)
        true

    scrollToAnchor: ->
      if @location.anchor?
        @controller.scrollToAnchor(@location.anchor)
        true

    scrollToTop: ->
      @controller.scrollToPosition(x: 0, y: 0)

    # Instrumentation

    recordTimingMetric: (name) ->
      @timingMetrics[name] ?= new Date().getTime()

    getTimingMetrics: ->
      Turbolinks.copyObject(@timingMetrics)

    # Private

    getHistoryMethodForAction = (action) ->
      switch action
        when "replace" then "replaceHistoryWithLocationAndRestorationIdentifier"
        when "advance", "restore" then "pushHistoryWithLocationAndRestorationIdentifier"

    shouldIssueRequest: ->
      if @action is "restore"
        not @hasCachedSnapshot()
      else
        true

    cacheSnapshot: ->
      unless @snapshotCached
        @controller.cacheSnapshot()
        @snapshotCached = true

    render: (callback) ->
      @cancelRender()
      @frame = requestAnimationFrame =>
        @frame = null
        callback.call(this)

    cancelRender: ->
      cancelAnimationFrame(@frame) if @frame


  class Turbolinks.Controller
    constructor: ->
      @history = new Turbolinks.History this
      @view = new Turbolinks.View this
      @scrollManager = new Turbolinks.ScrollManager this
      @restorationData = {}
      @clearCache()

    start: ->
      unless @started
        addEventListener("click", @clickCaptured, true)
        addEventListener("DOMContentLoaded", @pageLoaded, false)
        @scrollManager.start()
        @startHistory()
        @started = true
        @enabled = true

    disable: ->
      @enabled = false

    stop: ->
      if @started
        removeEventListener("click", @clickCaptured, true)
        removeEventListener("DOMContentLoaded", @pageLoaded, false)
        @scrollManager.stop()
        @stopHistory()
        @started = false

    clearCache: ->
      @cache = new Turbolinks.Cache 10

    visit: (location, options = {}) ->
      location = Turbolinks.Location.wrap(location)
      if @applicationAllowsVisitingLocation(location)
        if @locationIsVisitable(location)
          action = options.action ? "advance"
          @adapter.visitProposedToLocationWithAction(location, action)
        else
          window.location = location

    startVisitToLocationWithAction: (location, action, restorationIdentifier) ->
      if Turbolinks.supported
        restorationData = @getRestorationDataForIdentifier(restorationIdentifier)
        @startVisit(location, action, {restorationData})
      else
        window.location = location

    # History

    startHistory: ->
      @location = Turbolinks.Location.wrap(window.location)
      @restorationIdentifier = Turbolinks.uuid()
      @history.start()
      @history.replace(@location, @restorationIdentifier)

    stopHistory: ->
      @history.stop()

    pushHistoryWithLocationAndRestorationIdentifier: (location, @restorationIdentifier) ->
      @location = Turbolinks.Location.wrap(location)
      @history.push(@location, @restorationIdentifier)

    replaceHistoryWithLocationAndRestorationIdentifier: (location, @restorationIdentifier) ->
      @location = Turbolinks.Location.wrap(location)
      @history.replace(@location, @restorationIdentifier)

    # History delegate

    historyPoppedToLocationWithRestorationIdentifier: (location, @restorationIdentifier) ->
      if @enabled
        restorationData = @getRestorationDataForIdentifier(@restorationIdentifier)
        @startVisit(location, "restore", {@restorationIdentifier, restorationData, historyChanged: true})
        @location = Turbolinks.Location.wrap(location)
      else
        @adapter.pageInvalidated()

    # Snapshot cache

    getCachedSnapshotForLocation: (location) ->
      @cache.get(location)

    shouldCacheSnapshot: ->
      @view.getCacheControlValue() isnt "no-cache"

    cacheSnapshot: ->
      if @shouldCacheSnapshot()
        @notifyApplicationBeforeCachingSnapshot()
        snapshot = @view.getSnapshot()
        @cache.put(@lastRenderedLocation, snapshot)

    # Scrolling

    scrollToAnchor: (anchor) ->
      if element = document.getElementById(anchor)
        @scrollToElement(element)
      else
        @scrollToPosition(x: 0, y: 0)

    scrollToElement: (element) ->
      @scrollManager.scrollToElement(element)

    scrollToPosition: (position) ->
      @scrollManager.scrollToPosition(position)

    # Scroll manager delegate

    scrollPositionChanged: (scrollPosition) ->
      restorationData = @getCurrentRestorationData()
      restorationData.scrollPosition = scrollPosition

    # View

    render: (options, callback) ->
      @view.render(options, callback)

    viewInvalidated: ->
      @adapter.pageInvalidated()

    viewWillRender: (newBody) ->
      @notifyApplicationBeforeRender(newBody)

    viewRendered: ->
      @lastRenderedLocation = @currentVisit.location
      @notifyApplicationAfterRender()

    # Event handlers

    pageLoaded: =>
      @lastRenderedLocation = @location
      @notifyApplicationAfterPageLoad()

    clickCaptured: =>
      removeEventListener("click", @clickBubbled, false)
      addEventListener("click", @clickBubbled, false)

    clickBubbled: (event) =>
      if @enabled and @clickEventIsSignificant(event)
        if link = @getVisitableLinkForNode(event.target)
          if location = @getVisitableLocationForLink(link)
            if @applicationAllowsFollowingLinkToLocation(link, location)
              event.preventDefault()
              action = @getActionForLink(link)
              @visit(location, {action})

    # Application events

    applicationAllowsFollowingLinkToLocation: (link, location) ->
      event = @notifyApplicationAfterClickingLinkToLocation(link, location)
      not event.defaultPrevented

    applicationAllowsVisitingLocation: (location) ->
      event = @notifyApplicationBeforeVisitingLocation(location)
      not event.defaultPrevented

    notifyApplicationAfterClickingLinkToLocation: (link, location) ->
      Turbolinks.dispatch("turbolinks:click", target: link, data: { url: location.absoluteURL }, cancelable: true)

    notifyApplicationBeforeVisitingLocation: (location) ->
      Turbolinks.dispatch("turbolinks:before-visit", data: { url: location.absoluteURL }, cancelable: true)

    notifyApplicationAfterVisitingLocation: (location) ->
      Turbolinks.dispatch("turbolinks:visit", data: { url: location.absoluteURL })

    notifyApplicationBeforeCachingSnapshot: ->
      Turbolinks.dispatch("turbolinks:before-cache")

    notifyApplicationBeforeRender: (newBody) ->
      Turbolinks.dispatch("turbolinks:before-render", data: {newBody})

    notifyApplicationAfterRender: ->
      Turbolinks.dispatch("turbolinks:render")

    notifyApplicationAfterPageLoad: (timing = {}) ->
      Turbolinks.dispatch("turbolinks:load", data: { url: @location.absoluteURL, timing })

    # Private

    startVisit: (location, action, properties) ->
      @currentVisit?.cancel()
      @currentVisit = @createVisit(location, action, properties)
      @currentVisit.start()
      @notifyApplicationAfterVisitingLocation(location)

    createVisit: (location, action, {restorationIdentifier, restorationData, historyChanged} = {}) ->
      visit = new Turbolinks.Visit this, location, action
      visit.restorationIdentifier = restorationIdentifier ? Turbolinks.uuid()
      visit.restorationData = Turbolinks.copyObject(restorationData)
      visit.historyChanged = historyChanged
      visit.referrer = @location
      visit

    visitCompleted: (visit) ->
      @notifyApplicationAfterPageLoad(visit.getTimingMetrics())

    clickEventIsSignificant: (event) ->
      not (
        event.defaultPrevented or
        event.target.isContentEditable or
        event.which > 1 or
        event.altKey or
        event.ctrlKey or
        event.metaKey or
        event.shiftKey
      )

    getVisitableLinkForNode: (node) ->
      if @nodeIsVisitable(node)
        Turbolinks.closest(node, "a[href]:not([target])")

    getVisitableLocationForLink: (link) ->
      location = new Turbolinks.Location link.href
      location if @locationIsVisitable(location)

    getActionForLink: (link) ->
      link.getAttribute("data-turbolinks-action") ? "advance"

    nodeIsVisitable: (node) ->
      if container = Turbolinks.closest(node, "[data-turbolinks]")
        container.getAttribute("data-turbolinks") isnt "false"
      else
        true

    locationIsVisitable: (location) ->
      location.isPrefixedBy(@view.getRootLocation()) and location.isHTML()

    getCurrentRestorationData: ->
      @getRestorationDataForIdentifier(@restorationIdentifier)

    getRestorationDataForIdentifier: (identifier) ->
      @restorationData[identifier] ?= {}

  do ->
    Turbolinks.controller = controller = new Turbolinks.Controller
    controller.adapter = new Turbolinks.BrowserAdapter(controller)
    controller.start()

  Turbolinks
