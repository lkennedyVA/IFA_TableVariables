USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspProcessPNCException]
	CreatedBy: Larry Dugger
	Description: This procedure will process all of the unprocessed records

	Tables: [import].[File]
		,[import].[BulkException]

	Procedures: [import].[uspProcessConfirmationRequest]	returns error statuses
		,[import].[uspProcessReverseRequest]				returns error statuses

	History:
		2017-08-18 - LBD - Created
		2017-09-05 - LBD - Modified, included confirms also
		2017-10-25 - LBD - Modified, set StatusFlag according to result
		2021-06-04 - LBD - Corrected, this proc should be correctly setting the @iOrgId
			variable for the indicated procs. Original procedure is:
			[import].[uspProcessPNCExceptionOld]
		2021-06-15 - CBS - Added logic to set ClientAccepted = 1 when RuleBreak = 0 
			and ClientAccepted = 2 when RuleBreak = 1
		2025-01-14 - LXK - Replaced table variables and User Defined Table Types with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [import].[uspProcessPNCException](
	 @pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ProcessPNCException
	create table #ProcessFTBException(
		FTBExceptionId bigint
	);
	--DECLARE @tblItemConfirmRequest [ifa].[ItemConfirmRequestType];
	drop table if exists #ProcessPNCExceptionItemConfirm
	create table #ProcessPNCExceptionItemConfirm(
	[ItemKey] [nvarchar](25) NULL,
	[ClientItemId] [nvarchar](50) NULL,
	[ClientAccepted] [int] NULL,
	[Fee] [money] NULL,
	[PayoutAmount] [money] NULL
);
	DECLARE @iOrgId int
		,@iOrgClientId int
		,@bClientVerified bit = 0
		,@biPNCExceptionId bigint
		,@nvProcessKey nvarchar(25)
		,@nvItemKey nvarchar(25)
		,@nvExceptionCode nvarchar(25)
		,@iStatusFlag int = 1
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iAcceptedClientAcceptedId  int = [common].[ufnClientAccepted]('Accepted')
		,@iDeclinedClientAcceptedId  int = [common].[ufnClientAccepted]('Declined') --2021-06-15
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';

	SELECT @iOrgClientId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'PNCClnt';

	DECLARE csr_Reverse CURSOR FOR
	SELECT pe.PNCExceptionId,pe.ProcessKey,pe.ItemKey,et.Code,p.OrgId,CONVERT(BIT,CASE WHEN [common].[ufnOrgClientId](p.OrgId) = @iOrgClientId THEN 1 ELSE 0 END) as ClientVerified --0 wrong client
	FROM [import].[PNCException] pe
	INNER JOIN [import].[ExceptionType] et ON pe.ExceptionTypeId = et.ExceptionTypeId
	INNER JOIN [ifa].[Process] p WITH (READUNCOMMITTED) ON pe.ProcessKey = p.ProcessKey
	INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
								AND pe.ItemKey = i.ItemKey
	WHERE (et.Code = 'R'		--exception reversals
			OR et.Code = 'C')	--exception confirms --2017-09-05 LBD
		AND Processed = 0		--only those we haven't processed
	ORDER BY pe.PNCExceptionId;
	OPEN csr_Reverse
	FETCH csr_Reverse into @biPNCExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	WHILE @@FETCH_STATUS = 0 AND @bClientVerified = 1
	BEGIN
		SET @iStatusFlag = 1;
		IF @nvExceptionCode = 'R'
			EXECUTE [import].[uspProcessReverseRequest] @pnvProcessKey=@nvProcessKey, @pnvItemKey=@nvItemKey, @piOrgId=@iOrgId, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
		ELSE IF @nvExceptionCode = 'C'
		BEGIN
			--GRAB data
			INSERT INTO #ProcessPNCExceptionItemConfirm(ItemKey,ClientItemId,ClientAccepted,Fee,PayoutAmount)
			SELECT ItemKey,ClientItemId,CASE WHEN i.RuleBreak = 0 THEN @iAcceptedClientAcceptedId WHEN i.RuleBreak = 1 THEN @iDeclinedClientAcceptedId END,Fee, Amount --2021-06-15
			--SELECT ItemKey,ClientItemId,@iAcceptedClientAcceptedId,Fee, Amount --2021-06-15
			FROM [ifa].[Process] p WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
			WHERE p.ProcessKey = @nvProcessKey
				AND i.ItemKey = @nvItemKey;
			IF EXISTS (SELECT 'X' FROM #ProcessPNCExceptionItemConfirm)
				EXECUTE [import].[uspProcessConfirmationRequest] @pnvProcessKey=@nvProcessKey, @piOrgId=@iOrgId, @ptblItemConfirmRequest=#ProcessPNCExceptionItemConfirm, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
			ELSE
				SET @iStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
			DELETE FROM #ProcessPNCExceptionItemConfirm;
		END
		--UPDATE using the StatusFlag received
		UPDATE [import].[PNCException]
			SET Processed = 1
				,StatusFlag = @iStatusFlag
		WHERE PNCExceptionId = @biPNCExceptionId;

		FETCH csr_Reverse into @biPNCExceptionId,@nvProcessKey,@nvItemKey,@nvExceptionCode,@iOrgId,@bClientVerified;
	END
END
