USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspProcessTFBException]
	Created By: Chris Sharp
	Description: This procedure will process all of the unprocessed records

	Tables: [import].[ExceptionType]
		,[import].[TFBException]
		,[ifa].[Process]
		,[ifa].[Item] 

	Functions: [common].[ufnItemStatus]
		,[common].[ufnClientAccepted]

	Procedures: [import].[uspProcessConfirmationRequest]	returns error statuses
		,[import].[uspProcessReverseRequest]				returns error statuses

	History:
		2023-09-05 - CBS - VALID-1230: Created
		2025-01-15 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspProcessTFBException](
	 @pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ProcessTFBException
	create table #ProcessTFBException(
		TFBExceptionId bigint
	);
	DECLARE @tblItemConfirmRequest [ifa].[ItemConfirmRequestType];
	DECLARE @iOrgId int = 0
		,@iOrgClientId int = 0
		,@bClientVerified bit = 0
		,@biTFBExceptionId bigint
		,@nvProcessKey nvarchar(25)
		,@nvItemKey nvarchar(25)
		,@nvExceptionCode nvarchar(25)
		,@iStatusFlag int = 1
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iAcceptedClientAcceptedId  int = [common].[ufnClientAccepted]('Accepted')
		,@iDeclinedClientAcceptedId  int = [common].[ufnClientAccepted]('Declined') 
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'import';

	SELECT @iOrgClientId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'TFBClnt';

	DECLARE csr_Reverse CURSOR FOR
	SELECT pe.TFBExceptionId,pe.ProcessKey,pe.ItemKey,et.Code, p.OrgId, CONVERT(BIT,CASE WHEN [common].[ufnOrgClientId](p.OrgId) = @iOrgClientId THEN 1 ELSE 0 END) as ClientVerified --0 wrong client
	FROM [import].[TFBException] pe
	INNER JOIN [import].[ExceptionType] et ON pe.ExceptionTypeId = et.ExceptionTypeId
	INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) ON pe.ProcessKey = p.ProcessKey
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
								AND pe.ItemKey = i.ItemKey
	WHERE (et.Code = 'R'		--exception reversals
			OR et.Code = 'C')	--exception confirms 
		AND Processed = 0		--only those we haven't processed
	ORDER BY pe.TFBExceptionId;
	OPEN csr_Reverse
	FETCH csr_Reverse into @biTFBExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	WHILE @@FETCH_STATUS = 0 AND @bClientVerified = 1
	BEGIN
		SET @iStatusFlag = 1;
		IF @nvExceptionCode = 'R'
			EXECUTE [import].[uspProcessReverseRequest] @pnvProcessKey=@nvProcessKey, @pnvItemKey=@nvItemKey, @piOrgId=@iOrgId, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
		ELSE IF @nvExceptionCode = 'C'
		BEGIN
			--GRAB data
			INSERT INTO @tblItemConfirmRequest(ItemKey,ClientItemId,ClientAccepted,Fee,PayoutAmount)
			SELECT ItemKey,ClientItemId,CASE WHEN i.RuleBreak = 0 THEN @iAcceptedClientAcceptedId WHEN i.RuleBreak = 1 THEN @iDeclinedClientAcceptedId END,Fee, Amount 
			FROM [ifa].[Process] p WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
			WHERE p.ProcessKey = @nvProcessKey
				AND i.ItemKey = @nvItemKey;
			IF EXISTS (SELECT 'X' FROM @tblItemConfirmRequest)
				EXECUTE [import].[uspProcessConfirmationRequest] @pnvProcessKey=@nvProcessKey, @piOrgId=@iOrgId, @ptblItemConfirmRequest=@tblItemConfirmRequest, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
			ELSE
				SET @iStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
			DELETE FROM @tblItemConfirmRequest;
		END

		--UPDATE using the StatusFlag received
		UPDATE [import].[TFBException]
		SET Processed = 1
			,StatusFlag = @iStatusFlag
		WHERE TFBExceptionId = @biTFBExceptionId;

		FETCH csr_Reverse into @biTFBExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	END
END
